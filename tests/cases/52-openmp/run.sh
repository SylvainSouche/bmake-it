#!/bin/sh
# openmp-macro-req: OPENMP=yes builds a genuinely parallel `omp parallel
# for` program that really does use more than one thread -- not just a
# flag accepted silently. A compiler that can't actually support OpenMP
# gets a clean .error naming what to do, not an opaque compile failure.
set -eu
ROOT=$(pwd)

cd ws/Fw/app.m
bmake all OPENMP=yes >build.log 2>&1
grep -q -- "-fopenmp" build.log
out=$(./build/*/bin/app)
echo "$out"
threads=$(echo "$out" | sed 's/[^0-9]//g')
[ "$threads" -gt 1 ] || { echo "expected more than one thread to be used, got: $out" >&2; exit 1; }

bmake clean >/dev/null 2>&1

# A compiler that genuinely can't do OpenMP must fail loudly at parse
# time, not with an opaque compiler error deep in the build.
export REAL_CC=${CC:-cc}
if bmake all OPENMP=yes CC="sh $ROOT/fake/no-openmp-cc.sh" 2>err.log; then
    echo "expected OPENMP=yes to fail with a compiler that rejects -fopenmp" >&2
    exit 1
fi
grep -qi "does not accept -fopenmp" err.log

echo "openmp OK"
