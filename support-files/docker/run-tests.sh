#!/bin/bash
# Test-stage entrypoint. Runs `make unit` then `make test-drizzle`, and
# filters DTR failures against tests/skiplist.<phase>.txt so the container
# exits 0 when the only failures are ones we've already accepted.
#
# Set DTR_SKIPLIST to override the default skiplist path.
# Set DTR_BUILD_THREAD to control DTR's TCP port offset (default: $$).

set -uo pipefail

BUILD_DIR="${BUILD_DIR:-/opt/drizzle}"
SKIPLIST="${DTR_SKIPLIST:-${BUILD_DIR}/tests/skiplist.precise.txt}"
export DTR_BUILD_THREAD="${DTR_BUILD_THREAD:-$$}"

cd "${BUILD_DIR}"

echo "=== make unit ==="
if ! make unit; then
    echo "run-tests: unit tests failed" >&2
    exit 1
fi

echo
echo "=== make test-drizzle ==="
DTR_LOG=$(mktemp)
trap 'rm -f "${DTR_LOG}"' EXIT

if make test-drizzle 2>&1 | tee "${DTR_LOG}"; then
    echo "run-tests: all DTR tests passed"
    exit 0
fi

# DTR exited non-zero. Check whether every failure is on the skiplist.
if [ ! -f "${SKIPLIST}" ]; then
    echo "run-tests: DTR failed and no skiplist at ${SKIPLIST}" >&2
    exit 1
fi

failed=$(grep '\[ fail \]' "${DTR_LOG}" | awk '{print $1}' | sort -u)
allowed=$(grep -vE '^[[:space:]]*(#|$)' "${SKIPLIST}" | awk '{print $1}' | sort -u)
unexpected=$(comm -23 <(echo "${failed}") <(echo "${allowed}"))

if [ -z "${unexpected}" ]; then
    echo "run-tests: all DTR failures are skiplisted, treating as pass"
    exit 0
fi

echo "run-tests: unexpected DTR failures (not in ${SKIPLIST}):" >&2
echo "${unexpected}" >&2
exit 1
