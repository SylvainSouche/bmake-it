#!/bin/sh
set -eu
. "$BMK_TESTLIB"
cd ws/Fw
bmake -C libv.m all
# Linux/FreeBSD: libv.so.3 ; macOS: libv.3.dylib ; Windows: v.dll (the
# version lives in the DLL, never in its name: windows-shlib-versioninfo-
# uniform-naming-req)
find libv.m/build -name "$(shared_lib v 3)" | grep -q .
echo "versioned shlib OK"
