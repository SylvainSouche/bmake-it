#!/bin/sh
set -eu
. "$BMK_TESTLIB"
cd ws
bmake all
stage=$(pwd)/_stage
rm -rf "$stage"
bmake install DESTDIR="$stage" PREFIX=/opt/demo
# Expect $stage/opt/demo/bin/p or similar
find "$stage" -type f -name "$(prog_name p)" | grep -q .
echo "install OK"
