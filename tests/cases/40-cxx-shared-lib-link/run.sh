#!/bin/sh
# cxx-link-driver-selection-req: a C++ shared library AND the C++ program
# consuming it both must link with ${CXX} -- exercises exceptions thrown
# from inside the .so itself, not just from the top-level program.
set -eu
cd ws/Fw
bmake
bin=$(find . -type f -name app | head -1)
[ -n "$bin" ]
libdir=$(find . -type d -name lib | head -1)
[ -n "$libdir" ]
out=$(DYLD_LIBRARY_PATH="$libdir" LD_LIBRARY_PATH="$libdir" "$bin")
echo "$out" | grep -q "hello, world"
echo "$out" | grep -q "caught: empty name"
echo "cxx-shared-lib-link OK"
