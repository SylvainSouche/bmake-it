#!/bin/sh
set -eu
cd ws/Fw
bmake -C libv.m all
# Linux/FreeBSD: libv.so.3 ; macOS: libv.3.dylib
found=0
find libv.m/build -name 'libv.so.3' -o -name 'libv.3.dylib' | grep -q . && found=1
[ "$found" = "1" ]
echo "versioned shlib OK"
