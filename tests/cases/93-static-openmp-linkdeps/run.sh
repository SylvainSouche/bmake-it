#!/bin/sh
# static-lib-openmp-linkdeps-req (lasviewer round 8, item 2): a static
# library built with OPENMP=yes needs the OpenMP runtime at the final link,
# but a static library carries no dependency info. app.m below does NOT set
# OPENMP=; it must still link, because libwork.linkdeps records the runtime.
# Skips (77) where the compiler has no OpenMP runtime installed.
set -eu
cd ws
_cc=$(bmake -V '${CC}')
if ! printf '#include <omp.h>\nint main(void){return 0;}\n' | $_cc -fopenmp -x c - -o /dev/null >/dev/null 2>&1; then
    exit 77
fi
bmake >build.log 2>&1 || { echo "app.m (no OPENMP=) failed to link a static OPENMP=yes library:" >&2; tail -8 build.log >&2; exit 1; }
bin=$(find . -type f -name app -path '*/bin/*' | head -1)
[ -n "$bin" ]
"$bin"
ld=$(find . -name libwork.linkdeps | head -1)
grep -q -- "-fopenmp" "$ld"
echo "static-openmp-linkdeps OK"
