#!/bin/bash
# Local mirror of the Zuul CI jobs. Runs what `vouched` and `gate`
# run, against the local working tree.
#
# Default: amd64 only. Pass --arm64 to also do an arm64 configure+compile
# check (no tests on arm64 until Phase 10).
#
# Pass --no-dtr to skip the DTR suite (keep `make unit` and the build).

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "${REPO_ROOT}"

DO_ARM64=0
DO_DTR=1
for arg in "$@"; do
    case "${arg}" in
        --arm64)  DO_ARM64=1 ;;
        --no-dtr) DO_DTR=0 ;;
        -h|--help)
            sed -n '2,/^$/p' "$0" | sed 's/^# \?//'
            exit 0
            ;;
        *)
            echo "regress.sh: unknown arg: ${arg}" >&2
            exit 2
            ;;
    esac
done

echo "=== build stage (amd64) ==="
podman build --platform linux/amd64 --target=build -t drizzle:regress-build .

echo "=== test stage (amd64) ==="
podman build --platform linux/amd64 --target=test -t drizzle:regress-test .

if [ "${DO_DTR}" -eq 1 ]; then
    echo "=== run-tests (amd64) ==="
    podman run --rm drizzle:regress-test
else
    echo "=== run-tests skipped (--no-dtr) ==="
fi

if [ "${DO_ARM64}" -eq 1 ]; then
    echo "=== build stage (arm64) ==="
    podman build --platform linux/arm64 --target=build -t drizzle:regress-build-arm64 .
fi

echo
echo "regress.sh: all jobs green"
