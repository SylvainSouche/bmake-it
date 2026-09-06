#!/bin/sh
# share-overlay-copy-order-req: the three-layer share/ overlay (common ->
# <os> -> <os>_<arch>) must cover every presence combination, not just the
# "all three layers define the same file" case -- a file unique to any one
# layer must survive, and where two or more layers define the same file,
# the most specific layer present must win.
set -eu
cd ws

# TARGET=/TARGET_ARCH= are lazily-assigned (`=`) defaults in mk.common.mk,
# so `bmake -V TARGET` prints them unexpanded (a bmake quirk, not a bug
# here). OS_ARCH is built via `:=` (immediate expansion) and always
# resolves fully -- case 13-target-key already relies on this -- so derive
# TARGET/TARGET_ARCH by splitting it instead of querying them directly.
os_arch=$(bmake -C Fw -V OS_ARCH)
TARGET=${os_arch%%-*}
rest=${os_arch#*-}
ARCH=${rest%%-*}
osdir="Fw/share/$TARGET"
osarchdir="Fw/share/${TARGET}_${ARCH}"
mkdir -p Fw/share/common "$osdir" "$osarchdir"

# unique to a single layer
echo "common-only"  > Fw/share/common/only-common.txt
echo "os-only"       > "$osdir/only-os.txt"
echo "osarch-only"   > "$osarchdir/only-osarch.txt"

# common + os -- os must win
echo "common-version" > Fw/share/common/common-then-os.txt
echo "os-version"     > "$osdir/common-then-os.txt"

# common + os_arch -- os_arch must win
echo "common-version" > Fw/share/common/common-then-osarch.txt
echo "osarch-version" > "$osarchdir/common-then-osarch.txt"

# os + os_arch -- os_arch must win
echo "os-version"     > "$osdir/os-then-osarch.txt"
echo "osarch-version" > "$osarchdir/os-then-osarch.txt"

# common + os + os_arch -- os_arch (most specific) must win
echo "common-version" > Fw/share/common/all-three.txt
echo "os-version"     > "$osdir/all-three.txt"
echo "osarch-version" > "$osarchdir/all-three.txt"

bmake

sharedir=$(find Fw/build -type d -name share | head -1)
[ -n "$sharedir" ] || { echo "framework share dir not found" >&2; exit 1; }

check() {
    got=$(cat "$sharedir/$1")
    if [ "$got" != "$2" ]; then
        echo "$1: expected '$2', got '$got'" >&2
        exit 1
    fi
}

check only-common.txt         common-only
check only-os.txt              os-only
check only-osarch.txt          osarch-only
check common-then-os.txt       os-version
check common-then-osarch.txt   osarch-version
check os-then-osarch.txt       osarch-version
check all-three.txt            osarch-version

echo "share-overlay-cascade-matrix OK ($TARGET $ARCH)"
