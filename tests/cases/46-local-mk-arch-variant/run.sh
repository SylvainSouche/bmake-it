#!/bin/sh
# local-mk-arch-variant-req: mk.local.mk's hook cascade checks four
# conventional names per directory -- <phase>.mk, <phase>.${TOOLCHAIN}.mk,
# <phase>.${TARGET}.mk, <phase>.${TARGET}_${TARGET_ARCH}.mk -- ALL that
# exist and match, not just the most specific. Verifies every level fires
# when it matches, and a non-matching OS-keyed hook does NOT fire.
set -eu
cd ws/Fw/app.m

TARGET=$(bmake -V '${TARGET}')
TARGET_ARCH=$(bmake -V '${TARGET_ARCH}')
TOOLCHAIN=$(bmake -V '${TOOLCHAIN}')
[ -n "$TARGET" ] && [ -n "$TARGET_ARCH" ] && [ -n "$TOOLCHAIN" ]

mkdir -p mk
echo 'CFLAGS += -DHOOK_UNCONDITIONAL=1' > mk/pre.mk
echo 'CFLAGS += -DHOOK_TOOLCHAIN=1' > "mk/pre.${TOOLCHAIN}.mk"
echo 'CFLAGS += -DHOOK_TARGET=1' > "mk/pre.${TARGET}.mk"
echo 'CFLAGS += -DHOOK_TARGET_ARCH=1' > "mk/pre.${TARGET}_${TARGET_ARCH}.mk"
# A hook keyed to an OS that is deliberately never the real TARGET --
# must NOT fire.
echo 'CFLAGS += -DHOOK_SHOULD_NOT_FIRE=1' > mk/pre.bogus-os-never-real.mk

bmake >build.log 2>&1

grep -q -- "-DHOOK_UNCONDITIONAL=1" build.log
grep -q -- "-DHOOK_TOOLCHAIN=1" build.log
grep -q -- "-DHOOK_TARGET=1" build.log
grep -q -- "-DHOOK_TARGET_ARCH=1" build.log
if grep -q -- "-DHOOK_SHOULD_NOT_FIRE=1" build.log; then
    echo "a hook keyed to a different OS must not have fired" >&2
    exit 1
fi

echo "local-mk-arch-variant OK"
