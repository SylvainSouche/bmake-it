#!/bin/sh
# build-cross-vm.sh <from-platform> <ssh-port> <target-os> <target-arch> \
#                    <sysroot-tar> <artifact-out-dir> <log-file>
#
# Cross-builds examples/myworkspace/Hello from inside a provisioned VM,
# targeting <target-os>/<target-arch>, using <sysroot-tar> (uploaded and
# extracted inside the VM -- same reasoning as the Docker cross script:
# never extract a Linux sysroot directly onto a case-insensitive host fs,
# and here we're avoiding the macOS host filesystem entirely anyway since
# we're going through a VM).
set -eu
FROM_PLATFORM="${1:?}"
SSH_PORT="${2:?}"
TARGET_OS="${3:?}"
TARGET_ARCH="${4:?}"
SYSROOT_TAR="${5:?}"
OUT_DIR="${6:?}"
LOG="${7:?}"

HARNESS_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
BMK_ROOT=$(CDPATH= cd -- "$HARNESS_DIR/../.." && pwd)
. "$HARNESS_DIR/vm-lib.sh"

REMOTE_DIR="/root/bmk-cross"

case "$TARGET_OS" in
    linux)   SYSROOT_VAR=BMK_LINUX_SYSROOT ;;
    freebsd) SYSROOT_VAR=BMK_FREEBSD_SYSROOT ;;
    macos)   SYSROOT_VAR=BMK_MACOS_SYSROOT ;;
    netbsd)  SYSROOT_VAR=BMK_NETBSD_SYSROOT ;;
    *) echo "build-cross-vm.sh: unknown target-os '$TARGET_OS'" >&2; exit 2 ;;
esac

mkdir -p "$OUT_DIR" "$(dirname "$LOG")"
set +e
{
    vm_scp_in "$SSH_PORT" "$BMK_ROOT/mk" "$REMOTE_DIR/mk" \
        && vm_scp_in "$SSH_PORT" "$BMK_ROOT/examples" "$REMOTE_DIR/examples" \
        && vm_ssh "$SSH_PORT" "mkdir -p /root/sysroot-cross" \
        && tar -C "$(dirname "$SYSROOT_TAR")" -cf - "$(basename "$SYSROOT_TAR")" \
             | vm_ssh "$SSH_PORT" "cat > /root/sysroot-cross/sysroot.tar" \
        && vm_ssh "$SSH_PORT" "
            rm -rf /root/sysroot-cross/extracted && mkdir -p /root/sysroot-cross/extracted
            tar -xf /root/sysroot-cross/sysroot.tar -C /root/sysroot-cross/extracted
            cd $REMOTE_DIR/examples/myworkspace/Hello
            export BMK_MKDIR=$REMOTE_DIR/mk MAKESYSPATH=$REMOTE_DIR/mk:/usr/share/mk
            export $SYSROOT_VAR=/root/sysroot-cross/extracted
            bmake TARGET=$TARGET_OS TARGET_ARCH=$TARGET_ARCH
            file build/${TARGET_OS}-${TARGET_ARCH}/bin/hello
        "
} >"$LOG" 2>&1
status=$?
set -e
cat "$LOG"
if [ $status -eq 0 ] && tail -1 "$LOG" | grep -qi 'ELF\|Mach-O'; then
    vm_ssh "$SSH_PORT" "cd $REMOTE_DIR/examples/myworkspace/Hello && tar -cf - hello.m libgreet.m" \
        | (mkdir -p "$OUT_DIR/Hello" && tar -C "$OUT_DIR/Hello" -xf -)
    echo "PASS $(tail -1 "$LOG")" >"$LOG.status"
else
    echo "FAIL (exit $status)" >"$LOG.status"
fi
exit $status
