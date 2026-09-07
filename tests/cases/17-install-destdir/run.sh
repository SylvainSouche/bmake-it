#!/bin/sh
set -eu
cd ws
bmake all
stage=$(pwd)/_stage
rm -rf "$stage"
bmake install DESTDIR="$stage" PREFIX=/opt/demo
# Expect $stage/opt/demo/bin/p or similar
find "$stage" -type f -name p | grep -q .
echo "install OK"
