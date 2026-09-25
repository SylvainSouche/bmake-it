#!/bin/sh
# cxxstd-macro-req: CXXSTD defaults to c++17 -- a genuine C++20-only
# construct (consteval) fails to compile under the default, and builds
# and runs correctly once CXXSTD=c++20 is given.
set -eu
cd ws/Fw/app.m

if bmake all 2>err.log; then
    echo "expected consteval to fail under the default CXXSTD=c++17" >&2
    exit 1
fi
grep -qi "consteval" err.log

bmake clean >/dev/null 2>&1
bmake all CXXSTD=c++20 >build.log 2>&1
grep -q -- "-std=c++20" build.log
out=$(./build/*/bin/app)
[ "$out" = "16" ]

echo "cxxstd-default OK"
