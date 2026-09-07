#!/bin/sh
set -eu
cd ws/Fw
bmake -C libstat.m all
# Must have .a
find libstat.m/build -name 'libstat.a' | grep -q .
# Shared should not be the primary product when LIB_SHARED=NO
# (implementation may still emit .so as byproduct of bsd.lib.mk — our mk.lib.mk should not)
if find libstat.m/build -name 'libstat.so*' | grep -q .; then
    echo "WARN: shared lib present despite LIB_SHARED=NO (implementation risk)" >&2
    # Soft-fail? Spec says NO → static. Fail hard.
    exit 1
fi
echo "static-only OK"
