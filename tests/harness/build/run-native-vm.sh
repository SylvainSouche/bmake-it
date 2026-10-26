#!/bin/sh
# run-native-vm.sh <platform-id> <ssh-port> <toolchain> <bmake-cmd> <log-file>
#
# Runs the full suite inside an already-provisioned VM, over ssh.
# Ships the committed tests/archives/*.tar.gz as they are: repacking
# tests/cases in the guest would lose the empty directories git does not
# track (several cases rely on them).
# <bmake-cmd> is the remote bmake binary name (some BSD base systems already
# ARE bmake at /usr/bin/make; others install it as a separate 'bmake').
set -eu
PLATFORM="${1:?}"
SSH_PORT="${2:?}"
TOOLCHAIN="${3:?}"
BMAKE_CMD="${4:?}"
LOG="${5:?}"

HARNESS_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
BMK_ROOT=$(CDPATH= cd -- "$HARNESS_DIR/../.." && pwd)
. "$HARNESS_DIR/vm-lib.sh"

REMOTE_DIR="/root/bmk-matrix"

mkdir -p "$(dirname "$LOG")"
set +e
{
    # vm_scp_in copies a single path preserving its basename as a subdir
    # (right for a sysroot tar) -- here the *contents* of BMK_ROOT need to
    # land flattened into REMOTE_DIR, so tar multiple top-level dirs
    # directly, same style as the Docker cross scripts.
    (
        export COPYFILE_DISABLE=1
        tar --no-xattrs --no-acls --no-mac-metadata -C "$BMK_ROOT" -cf - mk scripts tests/harness tests/archives 2>/dev/null \
            || tar -C "$BMK_ROOT" -cf - mk scripts tests/harness tests/archives
    ) | vm_ssh "$SSH_PORT" "rm -rf '$REMOTE_DIR' && mkdir -p '$REMOTE_DIR' && tar -C '$REMOTE_DIR' -xf -" \
        && vm_ssh "$SSH_PORT" "
            # pkgsrc (NetBSD) and ports (FreeBSD) install outside the default PATH
            PATH=\$PATH:/usr/pkg/bin:/usr/pkg/sbin:/usr/local/bin:/usr/sbin; export PATH
            cd $REMOTE_DIR/tests/harness
            BMK_MKDIR=$REMOTE_DIR/mk BMK_SCRIPTS=$REMOTE_DIR/scripts BMAKE=$BMAKE_CMD TOOLCHAIN=$TOOLCHAIN sh ./run-tests.sh
        "
} >"$LOG" 2>&1
status=$?
set -e
cat "$LOG"
summary=$(grep -E '^pass=[0-9]+ ' "$LOG" | tail -1)
if [ $status -eq 0 ] && printf '%s' "$summary" | grep -q 'fail=0'; then
    echo "PASS $summary" >"$LOG.status"
else
    echo "FAIL (exit $status) $summary" >"$LOG.status"
fi
exit $status
