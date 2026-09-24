#!/bin/sh
# cxx-link-driver-selection-req: a pure-C module (SRCS all .c, no .cc/.cpp/
# .cxx) linking a static C++ library cannot be auto-detected -- LINK_CXX=yes
# is the explicit override for exactly this case. Proves both halves: the
# override is actually load-bearing (without it, the link genuinely fails
# on undefined C++ runtime symbols) and it works once set.
set -eu

cd ws/Fw/libcxxhelper.m
bmake copy-up
cd ../app.m

if bmake all 2>err.log; then
    echo "app should NOT link against a static C++ lib without LINK_CXX=yes" >&2
    exit 1
fi
grep -qi "undefined" err.log
bmake clean >/dev/null 2>&1 || true

{ echo "LINK_CXX=yes"; cat makefile; } > makefile.new && mv makefile.new makefile
bmake all

out=$(./build/*/bin/app)
echo "$out" | grep -q "hello from c++ static lib"
echo "c-prog-link-static-cxx-lib OK"
