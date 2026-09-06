#!/bin/sh
# exec-cross-docker.sh <artifact-dir> <target-os-arch-dir> <exec-platform> <log-file>
#
# Step B: actually runs a cross-built Hello binary under a Docker container
# matching its target (native or --platform-emulated), not just file(1).
set -eu
ARTIFACT_DIR="${1:?}"       # .../Hello, as copied out by build-cross-docker.sh
OS_ARCH="${2:?}"            # e.g. linux-amd64 (matches build/<OS_ARCH>/... layout)
EXEC_PLATFORM="${3:-}"      # e.g. linux/amd64, empty = host arch
LOG="${4:?}"

mkdir -p "$(dirname "$LOG")"
set +e
docker run --rm ${EXEC_PLATFORM:+--platform "$EXEC_PLATFORM"} \
    -v "$ARTIFACT_DIR:/hello:ro" debian:bookworm-slim sh -c "
    export LD_LIBRARY_PATH=/hello/hello.m/../build/$OS_ARCH/lib
    /hello/hello.m/build/$OS_ARCH/bin/hello
" >"$LOG" 2>&1
status=$?
set -e
cat "$LOG"
if [ $status -eq 0 ] && grep -q 'Hello, Bmake It!' "$LOG"; then
    echo "PASS executed OK" >"$LOG.status"
else
    echo "FAIL (exit $status)" >"$LOG.status"
fi
exit $status
