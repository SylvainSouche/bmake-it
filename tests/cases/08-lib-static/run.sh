#!/bin/sh
set -eu
. "$BMK_TESTLIB"
cd ws/Fw
bmake -C libstat.m all
# Must have the static library (libstat.a; stat.lib on Windows)
find libstat.m/build -name "$(static_lib stat)" | grep -q .
# Shared should not be the primary product when LIB_SHARED=NO
# (implementation may still emit .so as byproduct of bsd.lib.mk — our mk.lib.mk should not)
if find libstat.m/build -name "$(shared_lib stat)*" | grep -q .; then
    echo "WARN: shared lib present despite LIB_SHARED=NO (implementation risk)" >&2
    # Soft-fail? Spec says NO → static. Fail hard.
    exit 1
fi
echo "static-only OK"
