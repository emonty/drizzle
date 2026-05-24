# AGENTS.md — Drizzle Lay of the Land

Quick orientation for any agent or new contributor joining the Drizzle
revival. Read this first; then read the spec.

## What this is

Drizzle is a MySQL fork last actively developed around 2013. We are
reviving the project in 2026 as a **container-first** database server
with a single OS target and a single build system.

The revival is described in detail in
[`docs/specs/revival.rst`](docs/specs/revival.rst). That spec is the
load-bearing roadmap — every active workstream is a phase or sub-stack
of it. Read it before opening a PR.

## Current state

- Branch model: `drizzle-7.2` is the stable / default branch. Active
  revival work happens on `main`.
- Revival phase: Phases 0, 1, and 2 are landed (tests in container,
  dead-platform strip, performance baseline harness). **Phase 3**
  (container hygiene and Phase 0 follow-ups) is next; Phases 4–10
  are the LTS-bump ratchet that follows. Phase 11 (Pandora slim-down
  to `m4/drizzle.m4`) is paused — partially folded, deliberately
  deferred until after the LTS ratchet reaches 26.04. See the spec's
  Status preamble and Phase Map.
- Build target: Ubuntu 12.04 (Precise). We will ratchet LTS-by-LTS to
  26.04 as Phases 4–10 land.
- Base image: pulled from quay.io, never docker.io, so Zuul CI does
  not hit docker.io's pull rate limits. EOL releases use
  `quay.io/inaugust/unsafe-old-distro-danger:X.04` (apt sources
  pre-pointed at old-releases); Ubuntu 22.04 onward switches to
  `quay.io/opendevmirror/ubuntu`. See the spec's LTS-bump template.
- Architectures: `linux/amd64` and `linux/arm64`. amd64 is gating now;
  arm64 becomes gating in Phase 10.

## How to build and test

Inner loop — fast iteration, build only:

```console
podman build --platform linux/amd64 --target=build -t drizzle:build .
```

Verification — build + tests. The `test` stage carries the built tree
in the image layer and sets a default `CMD` that runs the test
entrypoint, so `podman run drizzle:test` runs tests against the
just-built tree at runtime. DTR's server and client both live inside
the container's netns, so default networking is sufficient — no
`--net=host`:

```console
podman build --platform linux/amd64 --target=test -t drizzle:test .
podman run --rm drizzle:test
```

arm64 readiness check (configure + compile, no tests yet):

```console
podman build --platform linux/arm64 --target=build -t drizzle:build-arm64 .
```

Local mirror of CI:

```console
./tools/regress.sh
```

Build deps live in `bindep.txt` (consumed by `bindep-rs` in the
Containerfile). Use `[compile platform:dpkg]` for build-time deps,
`[test platform:dpkg]` for DTR/test deps, and `[perf platform:dpkg]`
for the performance harness.

Performance baseline (Phase 2):

```console
podman build --platform linux/amd64 --target=perf .
```

The `perf` stage runs `tools/perf.sh` — a fixed sql-bench workload
under callgrind and massif, diffed against `perf/baseline.json`. See
`perf/README.rst`.

## Repo layout

- `Containerfile` — named stages: `base` (apt + bindep), `build`
  (autoreconf/configure/make), `test` (DTR runtime + entrypoint),
  `perf` (Phase 2 performance harness).
- `bindep.txt` — build/test/perf/runtime package list.
- `configure.ac` + `m4/` — autotools build. **Stay autotools.** Pandora
  macro layer is being slimmed into `m4/drizzle.m4` in Phase 11
  (paused until the LTS ratchet reaches 26.04); do not add new Pandora
  files.
- `drizzled/` — server source.
- `plugin/` — the in-tree plugins, each with a `plugin.ini`. Per-plugin
  `build_conditional` lines are being deleted in Phase 13; do not add
  new ones.
- `tests/` — DTR (`test-run.pl`) harness and suites.
- `unittests/` — boost.test unit tests. `make unit` runs them.
- `tools/run-tests.sh` — test stage entrypoint.
- `tools/perf.sh` — perf stage entrypoint; `tools/perf-report.pl`
  parses its output.
- `perf/` — performance baseline (`baseline.json`) and the vendored
  DBD::drizzle tarball. See `perf/README.rst`.
- `tools/regress.sh` — local CI mirror.
- `future-zuul.d/` — Zuul pipeline + job definitions (scaffolding;
  inert until CI is activated).
- `docs/` — Sphinx documentation. `docs/specs/` for engineering
  specifications.

## Working norms (from the spec — these are not optional)

### Strip the check, hardcode the answer

When excising an autoconf probe (Phases 1 and 11), preserve the flag /
define / behavior the probe would have set on amd64/arm64 Linux. The
goal is a `configure.ac` that does almost no probing but produces the
same `config.h` as the old one would have on our target. See the spec
for examples.

### Aggressive commit splitting; every commit green

- Deep stacks of small commits are loved. One semantic change per
  commit. Removing the haildb plugin is one commit; removing the
  tokyocabinet plugin is a separate commit.
- **Every commit must be fully green.** `podman build --target=build`
  succeeds, `podman build --target=test` succeeds, `make unit` exits
  0, `make test-drizzle` exits 0. No commit may knowingly break tests,
  even transiently.
- Bisect-load-bearing: future debugging walks dozens of small commits
  with `git bisect`. A "broken in the middle" commit defeats bisect
  for the rest of the stack.
- Zuul's `vouched` and `gate` pipelines run on every commit in a
  stack, not just the tip.
- Commit messages describe **why**, not what. The diff shows what.

### No gravestone comments

When code is removed, it is gone. Git log is the breadcrumb. Do not
leave `// removed X`, `/* was: ... */`, or `# this used to ...`
comments anywhere — source, m4, Makefile.am, plugin.ini, none.

### Multi-arch readiness

- Both targets (amd64, arm64) are 64-bit, little-endian, 8-byte
  pointer. Safe to hardcode.
- No x86-only intrinsics (SSE/AVX) or inline asm without aarch64
  fallback. Note any findings in the spec's "Multi-arch hazards"
  appendix.

## CI

CI runs on OpenDev Zuul. Pipelines:

- **check** — lint only (autoreconf syntax, configure dry-run, docs
  build). Runs on every patchset, unreviewed.
- **vouched** — full build + DTR + distcheck on both arches. Runs
  only after the OpenDev AI review agent has reviewed.
- **gate** — same jobs as vouched, re-run at merge time.
- **promote** — pushes the merged image to the permanent registry,
  tagged with the merge SHA, `latest`, and the phase name.

Everything must always pass. Flaky tests get fixed.

## Quick links

- [Revival spec](docs/specs/revival.rst) — the roadmap.
- [README.rst](README.rst) — top-level project description.
- [`docs/`](docs/) — Sphinx documentation tree.
- [Drizzle on OpenDev](https://opendev.org/inaugust/drizzle) — repo.
