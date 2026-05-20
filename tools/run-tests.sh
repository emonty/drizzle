#!/bin/bash
# Test-stage entrypoint. Runs `make unit` then `make test-drizzle`.
#
# Set DTR_BUILD_THREAD to control DTR's TCP port offset (default: $$).

set -uo pipefail

BUILD_DIR="${BUILD_DIR:-.}"
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

make test-drizzle 2>&1 | tee "${DTR_LOG}"
make_exit=${PIPESTATUS[0]}

failed=0

if [ "${make_exit}" -ne 0 ]; then
    echo "run-tests: DTR reported failures" >&2
    failed=1
fi

# server_detect (in drizzle / drizzledump) bails on a failed vc_release_id
# probe with this exact prefix. drizzletest tolerates the subprocess exit,
# so the test can still pass — surface it here instead of letting it slip.
if grep -q "Server version not detectable" "${DTR_LOG}"; then
    echo "run-tests: server_detect leaked 'version not detectable' through to test output" >&2
    failed=1
fi

if [ "${failed}" -ne 0 ]; then
    exit 1
fi

echo "run-tests: all DTR tests passed"
exit 0
