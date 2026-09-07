#!/bin/sh
# When a framework exists in BOTH the current workspace and a PARENT_WS
# workspace, the local one is built and used in its entirety -- including
# its share/ overlay. If the local copy is missing a more-specific (<os> or
# <os>_<arch>) override that the PARENT's copy of the same framework DOES
# have, the local build must NOT reach across the workspace boundary to
# pick it up; it falls back to its own less-specific (common) layer only.
# This mirrors prereq-local-shadows-parent's "local wins entirely, no
# merging" principle (REQ-headers-resolved-from-source-req), applied here
# to the share/ overlay (REQ-share-overlay-copy-order) instead of
# headers/libs.
set -eu

parent=$(CDPATH= cd parent && pwd)
sed "s|@@PARENT@@|$parent|" child/makefile.in > child/makefile

# See 37-share-overlay-cascade-matrix/run.sh: TARGET=/TARGET_ARCH= are
# lazily-assigned and print unexpanded via `-V`; derive them from OS_ARCH
# (immediate expansion) instead, as case 13-target-key already does.
os_arch=$(bmake -C parent/Res -V OS_ARCH)
TARGET=${os_arch%%-*}
rest=${os_arch#*-}
ARCH=${rest%%-*}

# The PARENT's copy has a more-specific override the child's copy lacks.
mkdir -p "parent/Res/share/$TARGET"
echo "target-specific" > "parent/Res/share/$TARGET/msg.txt"

cd child
bmake

sharedir=$(find Res/build -type d -name share | head -1)
[ -n "$sharedir" ] || { echo "child Res share dir not found" >&2; exit 1; }

got=$(cat "$sharedir/msg.txt")
[ "$got" = "general" ] || {
    echo "expected child's own common-layer value 'general' (no cross-workspace fallback), got '$got'" >&2
    exit 1
}

echo "share-overlay-no-parent-fallback OK ($TARGET $ARCH, got '$got')"
