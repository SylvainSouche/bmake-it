#!/bin/sh
set -eu
. "$BMK_TESTLIB"
cd ws/Fw
p=$(bmake -C hello.m -V PROG)
echo "PROG=$p"
# PROG carries the target's program suffix (hello.exe on Windows)
[ "$p" = "$(prog_name hello)" ]
lib=$(bmake -C libgreet.m -V LIB)
echo "LIB=$lib"
# Spec (prog-lib-default-to-module-name-req-v3): LIB= strips '.m' AND a
# leading 'lib', so libgreet.m -> LIB=greet, avoiding liblibgreet.so.
[ "$lib" = "greet" ]
