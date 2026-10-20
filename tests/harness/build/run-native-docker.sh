#!/bin/sh
# run-native-docker.sh <image> <platform-or-empty> <toolchain> <log-file>
#
# Runs the full 27-case suite inside a prebuilt, already-provisioned Docker
# image (packages baked in by provision/docker/Dockerfile.*, not installed
# here) under the given TOOLCHAIN. Used for the Docker-kind platforms.
set -eu
IMAGE="${1:?usage: run-native-docker.sh <image> <platform-or-empty> <toolchain> <log-file>}"
PLATFORM="${2:-}"
TOOLCHAIN="${3:?}"
LOG="${4:?}"

HARNESS_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
BMK_ROOT=$(CDPATH= cd -- "$HARNESS_DIR/../.." && pwd)

# Colima only bind-mounts $HOME by default -- stage under $HOME.
stage=$(mktemp -d "$HOME/.bmk-stage.XXXXXX")
trap 'rm -rf "$stage"' EXIT
cp -R "$BMK_ROOT"/. "$stage/" 2>/dev/null

mkdir -p "$(dirname "$LOG")"
# An emulated platform (--platform other than the host arch) is slow and
# timing-sensitive: retry a failing case once, visibly (run-tests.sh).
RETRY=0; [ -n "$PLATFORM" ] && RETRY=1
set +e
docker run --rm ${PLATFORM:+--platform "$PLATFORM"} -v "$stage:/work" "$IMAGE" sh -c "
    cd /work/tests/harness
    BMK_MKDIR=/work/mk BMK_SCRIPTS=/work/scripts TOOLCHAIN=$TOOLCHAIN RETRY_FAILED=${RETRY:-0} sh ./run-tests.sh
" >"$LOG" 2>&1
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
