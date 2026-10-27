#!/bin/sh
# cxxstd-macro-req: CXXSTD defaults to c++17 -- a genuine C++20-only
# construct (consteval) fails to compile under the default, and builds
# and runs correctly once CXXSTD=c++20 is given.
set -eu
. "$BMK_TESTLIB"
cd ws/Fw/app.m

# (both streams: cl.exe writes its diagnostics to stdout)
if bmake all >err.log 2>&1; then
    echo "expected consteval to fail under the default CXXSTD=c++17" >&2
    exit 1
fi
# gcc/clang name consteval; MSVC under /std:c++17 reports a syntax error on
# that line of main.cpp without naming it
grep -qiE "consteval|main\.cpp\(4\)" err.log

bmake clean >/dev/null 2>&1
bmake all CXXSTD=c++20 >build.log 2>&1
grep -q -- "-std=c++20" build.log
out=$(run_prog ./build/*/bin/app)
[ "$out" = "16" ]

echo "cxxstd-default OK"
