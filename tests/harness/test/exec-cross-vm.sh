#!/bin/sh
# exec-cross-vm.sh <artifact-dir> <os-arch> <platform-id> <log-file>
#
# Step B for a VM target: runs a cross-built Hello binary inside the target's
# own guest (the real kernel and libc it was built for), not just file(1).
# <artifact-dir> is .../Hello as copied out by build-cross-*.sh; <os-arch> the
# build key (freebsd-arm64). The guest must be up (vm.sh up <platform-id>).
# @impl 0f87-6ad7-1929-a1bb
set -eu
ARTIFACT_DIR="${1:?}"; OS_ARCH="${2:?}"; PLATFORM="${3:?}"; LOG="${4:?}"
HARNESS_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
mkdir -p "$(dirname "$LOG")"
set +e
(
    export COPYFILE_DISABLE=1
    tar --no-xattrs --no-acls --no-mac-metadata -C "$(dirname "$ARTIFACT_DIR")" -cf - "$(basename "$ARTIFACT_DIR")" 2>/dev/null \
        || tar -C "$(dirname "$ARTIFACT_DIR")" -cf - "$(basename "$ARTIFACT_DIR")"
) | sh "$HARNESS_DIR/vm.sh" ssh "$PLATFORM" "rm -rf /root/xrun && mkdir -p /root/xrun && tar -xf - -C /root/xrun" >"$LOG" 2>&1 \
  && sh "$HARNESS_DIR/vm.sh" ssh "$PLATFORM" "
        d=/root/xrun/$(basename "$ARTIFACT_DIR")
        LD_LIBRARY_PATH=\$d/build/$OS_ARCH/lib \$d/hello.m/build/$OS_ARCH/bin/hello
     " >>"$LOG" 2>&1
status=$?
set -e
cat "$LOG"
if [ $status -eq 0 ] && grep -q 'Hello, Bmake It!' "$LOG"; then
    echo "PASS executed OK on $PLATFORM" >"$LOG.status"
else
    echo "FAIL (exit $status)" >"$LOG.status"
fi
exit $status
