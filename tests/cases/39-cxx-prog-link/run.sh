#!/bin/sh
# cxx-link-driver-selection-req: a C++ program (SRCS contains .cpp) must
# link with ${CXX}, not ${CC} -- otherwise the C++ runtime support symbols
# (exception handling, etc.) are undefined and the link itself fails.
set -eu
cd ws/Fw/app.m
bmake all
out=$(./build/*/bin/app)
echo "$out" | grep -q "cxx link works"
echo "$out" | grep -q "exception path ok"
echo "cxx-prog-link OK"
