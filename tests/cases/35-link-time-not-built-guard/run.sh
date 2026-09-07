#!/bin/sh
# link-time-not-yet-built-guard-req: linking a module whose LIBS= entry has
# not actually been built yet must fail with an explicit diagnostic naming
# the missing dependency, not an opaque linker error -- and once the
# dependency IS built, the same module must link/run normally.
set -eu

cd ws/Fw/app.m
if bmake all 2>err.log; then
    echo "app should not link before libg is built" >&2
    exit 1
fi
grep -qi "prerequisite library g" err.log
grep -qi "has not been built yet" err.log
! grep -qi "No such file or directory" err.log
cd ../../..

# Build in correct order via the framework itself: libg.m first (LIBS=g
# ordering), including its copy-up into the framework's own build/lib/,
# which is exactly where the guard above searches.
(cd ws/Fw && bmake)

bin=$(find ws -type f -name app | head -1)
[ -n "$bin" ] || { echo "app binary not found" >&2; exit 1; }
libdir=$(find ws/Fw/build -type d -name lib | head -1)
[ -n "$libdir" ] || { echo "Fw build lib dir not found" >&2; exit 1; }
DYLD_LIBRARY_PATH="$libdir" LD_LIBRARY_PATH="$libdir" "$bin" >/dev/null

echo "link-time-not-built-guard OK"
