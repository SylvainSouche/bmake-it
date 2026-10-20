#!/bin/sh
# build-cross-docker.sh <from-image> <from-platform-or-empty> <target-os> \
#                        <target-arch> <sysroot-tar> <artifact-out-dir> <log-file>
#
# Cross-builds examples/myworkspace/Hello from inside <from-image>, targeting
# <target-os>/<target-arch> using <sysroot-tar> (extracted inside the
# container, never onto the host -- avoids the macOS case-insensitive
# filesystem corrupting Linux kernel headers, found empirically). Copies the
# built artifact tree out to <artifact-out-dir> for Step B execution later.
set -eu
FROM_IMAGE="${1:?}"
FROM_PLATFORM="${2:-}"
TARGET_OS="${3:?}"
TARGET_ARCH="${4:?}"
SYSROOT_TAR="${5:?}"
OUT_DIR="${6:?}"
LOG="${7:?}"

HARNESS_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
BMK_ROOT=$(CDPATH= cd -- "$HARNESS_DIR/../.." && pwd)

stage=$(mktemp -d "$HOME/.bmk-stage.XXXXXX")
trap 'rm -rf "$stage"' EXIT
cp -R "$BMK_ROOT"/. "$stage/" 2>/dev/null
# The container runtime (Colima) shares $HOME but not an external drive: the
# cache may live on one ($BMK_CACHE), so mount a local copy of the sysroot.
mkdir -p "$stage/.sysroot-in" && cp "$SYSROOT_TAR" "$stage/.sysroot-in/sysroot.tar"
SYSROOT_TAR="$stage/.sysroot-in/sysroot.tar"

mkdir -p "$OUT_DIR" "$(dirname "$LOG")"

# BMK_LINUX_SYSROOT is the variable name mk.toolchain.llvm.mk actually
# reads for TARGET=linux regardless of which arch it targets -- the arch
# distinction lives in the sysroot's own contents, not the variable name.
case "$TARGET_OS" in
    linux)   SYSROOT_VAR=BMK_LINUX_SYSROOT ;;
    freebsd) SYSROOT_VAR=BMK_FREEBSD_SYSROOT ;;
    macos)   SYSROOT_VAR=BMK_MACOS_SYSROOT; SYSROOT_SUB=/MacOSX.sdk ;;  # the SDK tar nests it
    netbsd)  SYSROOT_VAR=BMK_NETBSD_SYSROOT ;;
    *) echo "build-cross-docker.sh: unknown target-os '$TARGET_OS'" >&2; exit 2 ;;
esac

set +e
docker run --rm ${FROM_PLATFORM:+--platform "$FROM_PLATFORM"} \
    -v "$stage:/work" -v "$SYSROOT_TAR:/sysroot.tar:ro" \
    "$FROM_IMAGE" sh -c "
    set -e
    mkdir -p /sysroot && tar -xf /sysroot.tar -C /sysroot
    cd /work/examples/myworkspace/Hello
    export BMK_MKDIR=/work/mk MAKESYSPATH=/work/mk:/usr/share/mk
    export $SYSROOT_VAR=/sysroot${SYSROOT_SUB:-}
    bmake TARGET=$TARGET_OS TARGET_ARCH=$TARGET_ARCH || {
        # the module logs live in this throw-away workspace: show them now
        for _l in \$(find /work/examples/myworkspace/Hello -path \"*runs/latest/build.log\"); do echo \"--- \$_l\"; tail -12 \"\$_l\"; done
        exit 1
    }
    file build/${TARGET_OS}-${TARGET_ARCH}/bin/hello
" >"$LOG" 2>&1
status=$?
set -e
cat "$LOG"
if [ $status -eq 0 ] && tail -1 "$LOG" | grep -qi 'ELF\|Mach-O'; then
    cp -R "$stage/examples/myworkspace/Hello" "$OUT_DIR/"
    echo "PASS $(tail -1 "$LOG")" >"$LOG.status"
else
    echo "FAIL (exit $status)" >"$LOG.status"
fi
exit $status
