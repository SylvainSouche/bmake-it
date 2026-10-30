#!/bin/sh
# run-native-macos.sh <toolchain> <log-file>
#
# Runs the full suite (the committed tests/archives, not a repack) inside the macOS tart VM, over
# plain key-based ssh -- provision-macos-vm.sh installs this host's public
# key into the VM's authorized_keys during bootstrap, so nothing here needs
# to juggle expect/password auth.
set -eu
TOOLCHAIN="${1:?}"
LOG="${2:?}"

HARNESS_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
BMK_ROOT=$(CDPATH= cd -- "$HARNESS_DIR/../.." && pwd)

# The macOS guest is a tart VM (Virtualization.framework); platforms.mk names it.
# shellcheck disable=SC1091
. "$HARNESS_DIR/lib/env.sh"
VM_NAME=$(plat macos_arm64 TARTVM); VM_NAME=${VM_NAME:-rade-bmake-macos}
command -v tart >/dev/null 2>&1 || { echo "run-native-macos.sh: tart not found (brew/port install tart)" >&2; exit 2; }
if ! tart list 2>/dev/null | grep -E "[[:space:]]${VM_NAME}[[:space:]]" | grep -q running; then
    echo "run-native-macos.sh: starting tart VM $VM_NAME" >&2
    nohup tart run "$VM_NAME" --no-graphics >"${TMPDIR:-/tmp}/tart-$VM_NAME.log" 2>&1 &
fi
IP=""; n=0
while [ -z "$IP" ] && [ "$n" -lt 180 ]; do
    IP=$(tart ip "$VM_NAME" 2>/dev/null || true)
    [ -n "$IP" ] || { sleep 3; n=$((n + 3)); }
done
[ -n "$IP" ] || { echo "run-native-macos.sh: $VM_NAME never got an IP" >&2; exit 2; }

REMOTE_DIR="/Users/admin/bmk-matrix"
SSH_OPTS="-F /dev/null -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=15 -o BatchMode=yes"
n=0; until ssh $SSH_OPTS "admin@$IP" true >/dev/null 2>&1 || [ "$n" -ge 120 ]; do sleep 5; n=$((n + 5)); done

mkdir -p "$(dirname "$LOG")"
set +e
{
    COPYFILE_DISABLE=1 tar --no-xattrs --no-mac-metadata -C "$BMK_ROOT" -cf - mk scripts contrib tests/harness tests/archives examples \
        | ssh $SSH_OPTS "admin@$IP" "rm -rf $REMOTE_DIR && mkdir -p $REMOTE_DIR && tar -C $REMOTE_DIR -xf -" \
        && ssh $SSH_OPTS "admin@$IP" "
            cd $REMOTE_DIR/tests/harness
            # Non-interactive ssh gets PATH=/usr/bin:/bin:/usr/sbin:/sbin --
            # no /opt/local/bin. Without this, mk.toolchain.gcc.mk's own
            # 'command -v gcc' search would silently resolve to Apple
            # clang's /usr/bin/gcc wrapper instead of the real MacPorts
            # gcc, defeating the whole point of the gcc-toolchain leg.
            export PATH=/opt/local/bin:/opt/local/sbin:\$PATH
            BMK_MKDIR=$REMOTE_DIR/mk BMK_SCRIPTS=$REMOTE_DIR/scripts TOOLCHAIN=$TOOLCHAIN sh ./run-tests.sh
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
