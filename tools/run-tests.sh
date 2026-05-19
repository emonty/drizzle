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

if make test-drizzle 2>&1 | tee "${DTR_LOG}"; then
    echo "run-tests: all DTR tests passed"
    exit 0
fi

echo "run-tests: DTR reported failures" >&2
exit 1
