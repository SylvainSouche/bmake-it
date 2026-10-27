#!/bin/sh
# run-native-host.sh <platform-id> <toolchain> <log-file>
#
# A native cell whose platform is THIS machine (KIND_<p> = host): runs the
# suite (the committed tests/archives) right here, no container or guest.
# Used for windows_amd64, where the machine running matrix.sh is the
# Windows host (Cygwin) -- harness-windows-host-cells-req. The platform
# names the host it needs (HOSTOS_<p>, a `uname -s` glob); on any other
# machine the cell is BLOCKED with that reason rather than run wrongly.
# @impl 7854-6adf-8cd3-e408
set -u
P="${1:?}"; TOOLCHAIN="${2:?}"; LOG="${3:?}"
# <toolchain>+<abi> (matrix.tsv: llvm+mingw) also forces ABI= for the suite.
ABI=""
case "$TOOLCHAIN" in *+*) ABI=${TOOLCHAIN#*+}; TOOLCHAIN=${TOOLCHAIN%%+*} ;; esac

HARNESS_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
BMK_ROOT=$(CDPATH= cd -- "$HARNESS_DIR/../.." && pwd)
# shellcheck disable=SC1091
. "$HARNESS_DIR/lib/env.sh"
mkdir -p "$(dirname "$LOG")"

want=$(plat "$P" HOSTOS)
case "$(uname -s)" in
    $want) ;;
    *) echo "BLOCKED $P runs on a '$want' host (uname -s); this is $(uname -s)" >"$LOG.status"
       cat "$LOG.status"; exit 0 ;;
esac

# The system mk directory this host's bmake uses (Cygwin: /usr/share/bmake/mk).
sysmk=$(plat "$P" SYSMK)

# TOOLCHAIN=msvc from the cached EWDK (msvc-ewdk-root-req): mount the ISO in
# BMK_CACHE/msvc read-only unless it already is, and hand its drive to the
# suite as BMK_EWDK_ROOT. A missing or unmountable ISO blocks the cell.
ewdk=""
if [ "$TOOLCHAIN" = msvc ] && [ -z "${BMK_EWDK_ROOT:-}" ]; then
    iso=$(ls "$BMK_CACHE"/msvc/EWDK_*.iso 2>/dev/null | head -1)
    if [ -z "$iso" ]; then
        echo "BLOCKED no EWDK ISO in $BMK_CACHE/msvc" >"$LOG.status"; cat "$LOG.status"; exit 0
    fi
    winiso=$(cygpath -w "$iso")
    letter=$(powershell.exe -NoProfile -Command "\$i = Get-DiskImage -ImagePath '$winiso'; if (-not \$i.Attached) { \$i = Mount-DiskImage -ImagePath '$winiso' -Access ReadOnly -PassThru }; (\$i | Get-Volume).DriveLetter" 2>/dev/null | tr -d '\r\n ')
    if [ -z "$letter" ]; then
        echo "BLOCKED could not mount $iso (check its sha256 against $BMK_CACHE/msvc/MANIFEST.sha256)" >"$LOG.status"; cat "$LOG.status"; exit 0
    fi
    ewdk="$letter:\\"
fi

set +e
(
    cd "$HARNESS_DIR" &&
    env ${sysmk:+BMK_SYS_MK="$sysmk"} ${ewdk:+BMK_EWDK_ROOT="$ewdk"} BMK_MKDIR="$BMK_ROOT/mk" BMK_SCRIPTS="$BMK_ROOT/scripts" \
        TOOLCHAIN="$TOOLCHAIN" ${ABI:+ABI="$ABI"} sh ./run-tests.sh
) >"$LOG" 2>&1
status=$?
set -e
summary=$(grep -E '^pass=[0-9]+ ' "$LOG" | tail -1)
if [ $status -eq 0 ] && printf '%s' "$summary" | grep -q 'fail=0'; then
    echo "PASS $summary" >"$LOG.status"
else
    echo "FAIL (exit $status) $summary" >"$LOG.status"
fi
cat "$LOG.status"
exit 0
