#!/bin/sh
set -eu
cd ws/Fw
p=$(bmake -C hello.m -V PROG)
echo "PROG=$p"
[ "$p" = "hello" ]
lib=$(bmake -C libgreet.m -V LIB)
echo "LIB=$lib"
# Spec (prog-lib-default-to-module-name-req-v3): LIB= strips '.m' AND a
# leading 'lib', so libgreet.m -> LIB=greet, avoiding liblibgreet.so.
[ "$lib" = "greet" ]
