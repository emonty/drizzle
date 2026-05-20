#!/bin/bash
# Phase 1.5 performance harness — see docs/specs/revival.rst.
#
# Runs a fixed, deterministic workload (a subset of sql-bench) against an
# installed drizzled: once under callgrind to count instructions, once
# under massif to measure peak heap. Emits a JSON metrics blob and diffs
# it against the committed baseline.
#
# Wall-clock time is deliberately ignored — CI runs on shared hardware.
# callgrind counts instructions by simulation, so the numbers are
# reproducible and identical on any host.
#
# This script is the entrypoint of the Containerfile `perf` stage.

set -uo pipefail

BUILD_DIR="${BUILD_DIR:-.}"
cd "${BUILD_DIR}"
SRC_DIR="$(pwd)"

PERF_DIR="${SRC_DIR}/perf"
BASELINE="${PERF_DIR}/baseline.json"
METRICS="${PERF_DIR}/last-run.json"
SQLBENCH="${SRC_DIR}/tests/test_tools/sql-bench"
# Fetched by the Containerfile `perf` stage via ADD.
DBD_TARBALL="${DBD_TARBALL:-/opt/DBD-drizzle-0.304.tar.gz}"

WORK="$(mktemp -d)"
trap 'stop_server 2>/dev/null; rm -rf "${WORK}"' EXIT

# Discovered by setup() after `make install`.
DRIZZLED=""
DRIZZLE=""

# Fixed workload parameters. Changing any of these invalidates the
# committed baseline — rebaseline deliberately, in its own commit.
#
# test-insert is the most comprehensive single sql-bench script
# (inserts, key reads, ranges, updates, deletes). --small-test divides
# its sizes by 100, so LOOP_COUNT=10000 yields ~100 rows — small
# enough for callgrind's ~50x slowdown, still exercising every path.
LOOP_COUNT=10000
BENCH_TESTS="test-insert"
MYSQL_PORT=37306
DRIZZLE_PORT=37307

SERVER_PID=0

banner() { echo; echo "=== perf: $* ==="; }
die()    { echo "perf: ERROR: $*" >&2; exit 1; }

# --------------------------------------------------------------------
# Install Drizzle so we measure a clean binary (no libtool wrapper under
# valgrind), and build the vendored DBD::drizzle against the freshly
# installed libdrizzle.
# --------------------------------------------------------------------
setup() {
  banner "installing drizzle"
  make install >/dev/null || die "make install failed"
  ldconfig

  DRIZZLED="$(find /usr/local -type f -name drizzled -perm -u+x 2>/dev/null | head -1)"
  DRIZZLE="$(find /usr/local -type f -name drizzle -perm -u+x 2>/dev/null | head -1)"
  [ -n "${DRIZZLED}" ] || die "installed drizzled not found"
  [ -n "${DRIZZLE}" ]  || die "installed drizzle client not found"
  echo "perf: drizzled = ${DRIZZLED}"
  echo "perf: drizzle  = ${DRIZZLE}"

  banner "building DBD::drizzle from ${DBD_TARBALL}"
  [ -f "${DBD_TARBALL}" ] || die "vendored DBD::drizzle tarball missing"
  tar xzf "${DBD_TARBALL}" -C "${WORK}" || die "cannot unpack DBD::drizzle"
  (
    cd "${WORK}"/DBD-drizzle-* || exit 1
    # DBD::drizzle 0.304 predates the Perl 5.10 interpreter-variable
    # rename; Perl 5.14 only exposes the PL_-prefixed names. Each bare
    # symbol below occurs once as the interpreter global and collides
    # with nothing else in dbdimp.c, so a word-boundary rewrite is safe.
    sed -i -E 's/\bsv_yes\b/PL_sv_yes/g;
               s/\bsv_undef\b/PL_sv_undef/g;
               s/\bdirty\b/PL_dirty/g;
               s/\bperl_destruct_level\b/PL_perl_destruct_level/g' dbdimp.c
    # libdrizzle headers/lib land under /usr/local from `make install`.
    # --testuser must be passed explicitly: Makefile.PL's Configure()
    # otherwise falls through to a fatal "Unknown configuration
    # parameter" for it.
    perl Makefile.PL \
      --testuser=root \
      --cflags="-I/usr/local/include" \
      --libs="-L/usr/local/lib -ldrizzle -lz -lm" </dev/null \
      && make && make install
  ) || die "DBD::drizzle build failed"
  perl -MDBD::drizzle -e1 || die "DBD::drizzle not loadable after install"
}

# --------------------------------------------------------------------
# Server lifecycle. $1 is a (possibly empty) command prefix — the
# valgrind invocation — word-split intentionally.
# --------------------------------------------------------------------
start_server() {
  local prefix="$1"
  local datadir="${WORK}/data"
  rm -rf "${datadir}"; mkdir -p "${datadir}"

  # Run drizzled as root — the container's only user.
  ${prefix} "${DRIZZLED}" \
      --no-defaults \
      --user=root \
      --datadir="${datadir}" \
      --pid-file="${WORK}/drizzled.pid" \
      --mysql-protocol.port=${MYSQL_PORT} \
      --drizzle-protocol.port=${DRIZZLE_PORT} \
      >"${WORK}/drizzled.log" 2>&1 &
  SERVER_PID=$!

  banner "waiting for drizzled (pid ${SERVER_PID})"
  local i
  for i in $(seq 1 180); do
    if "${DRIZZLE}" --silent --host=127.0.0.1 --port=${MYSQL_PORT} \
         --user=root --password= -e 'SELECT 1' >/dev/null 2>&1; then
      echo "perf: drizzled is up"
      return 0
    fi
    kill -0 "${SERVER_PID}" 2>/dev/null \
      || { cat "${WORK}/drizzled.log"; die "drizzled exited during startup"; }
    sleep 1
  done
  cat "${WORK}/drizzled.log"
  die "drizzled did not become reachable"
}

stop_server() {
  [ "${SERVER_PID}" -ne 0 ] 2>/dev/null || return 0
  "${DRIZZLE}" --host=127.0.0.1 --port=${MYSQL_PORT} --user=root \
      --password= --connect-timeout=5 --silent --shutdown >/dev/null 2>&1
  local i
  for i in $(seq 1 60); do
    kill -0 "${SERVER_PID}" 2>/dev/null || { SERVER_PID=0; return 0; }
    sleep 1
  done
  kill -9 "${SERVER_PID}" 2>/dev/null
  SERVER_PID=0
}

# --------------------------------------------------------------------
# The workload: a fixed subset of sql-bench. Deterministic — sql-bench's
# "random" keys are a fixed shuffle, and --loop-count is pinned.
# --------------------------------------------------------------------
run_workload() {
  "${DRIZZLE}" --host=127.0.0.1 --port=${MYSQL_PORT} --user=root --password= \
      -e 'CREATE SCHEMA IF NOT EXISTS test' || die "cannot create test schema"

  local t
  for t in ${BENCH_TESTS}; do
    banner "sql-bench: ${t}"
    # No --password: sql-bench's Getopt rejects an empty value, and an
    # empty password is the default anyway. --time-limit is set absurdly
    # high so sql-bench never switches a test to wall-clock "estimated"
    # mode — under callgrind it would otherwise truncate and the
    # instruction count would stop being reproducible.
    ( cd "${SQLBENCH}" && perl "./${t}" \
        --server=drizzle --host=127.0.0.1 --database=test \
        --user=root --loop-count=${LOOP_COUNT} --small-test --time-limit=86400 \
        --connect-options="port=${DRIZZLE_PORT}" --silent ) \
      || die "sql-bench ${t} failed"
  done
}

# --------------------------------------------------------------------
# Measurement passes.
# --------------------------------------------------------------------
callgrind_pass() {
  banner "callgrind pass"
  local out="${WORK}/callgrind.out"
  # Instrument the whole process. Toggling instrumentation mid-run
  # would need callgrind_control -> vgdb -> ptrace, which the build
  # container's kernel (yama ptrace_scope) blocks. Server boot is a
  # stable constant, so counting it too is fine for tracking deltas.
  start_server "valgrind --tool=callgrind \
      --cache-sim=yes --branch-sim=yes --trace-children=no \
      --callgrind-out-file=${out}"
  run_workload
  stop_server   # callgrind dumps ${out} when drizzled exits

  [ -s "${out}" ] || die "no callgrind output produced"
  callgrind_annotate "${out}" >"${WORK}/callgrind.txt" \
    || die "callgrind_annotate failed"
}

massif_pass() {
  banner "massif pass"
  local out="${WORK}/massif.out"
  start_server "valgrind --tool=massif --trace-children=no \
      --massif-out-file=${out}"
  run_workload
  stop_server
  [ -s "${out}" ] || die "no massif output produced"
  cp "${out}" "${WORK}/massif.txt"
}

# --------------------------------------------------------------------
# Parse the raw tool output and binary sizes into JSON, then diff
# against the committed baseline.
# --------------------------------------------------------------------
report() {
  banner "report"
  local sizes="${WORK}/sizes.txt"
  : >"${sizes}"
  size "${DRIZZLED}" >>"${sizes}" 2>/dev/null
  local so
  for so in $(find /usr/local -name '*.so' -path '*drizzle*plugin*' 2>/dev/null | sort); do
    size "${so}" >>"${sizes}" 2>/dev/null
  done

  mkdir -p "${PERF_DIR}"
  perl "${SRC_DIR}/tools/perf-report.pl" \
      "${WORK}/callgrind.txt" "${WORK}/massif.txt" "${sizes}" \
      >"${METRICS}" || die "perf-report.pl failed"

  echo
  echo "=== PERF METRICS BEGIN ==="
  cat "${METRICS}"
  echo "=== PERF METRICS END ==="
  echo

  if [ -f "${BASELINE}" ]; then
    perl "${SRC_DIR}/tools/perf-report.pl" --diff "${BASELINE}" "${METRICS}"
  else
    echo "perf: no committed baseline (${BASELINE}); this run is a baseline candidate."
  fi
}

main() {
  command -v valgrind           >/dev/null || die "valgrind not installed"
  command -v callgrind_annotate >/dev/null || die "callgrind_annotate not installed"
  setup
  callgrind_pass
  massif_pass
  report
  # Non-gating: the harness reports, it does not fail the build.
  banner "done"
}

main "$@"
