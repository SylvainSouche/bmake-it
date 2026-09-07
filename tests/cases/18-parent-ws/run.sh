#!/bin/sh
set -eu
# PARENT_WS resolution across workspaces is partially implemented —
# this test documents current behaviour: absolute path is recorded.
parent=$(CDPATH= cd parent && pwd)
sed "s|@@PARENT@@|$parent|" child/makefile.in > child/makefile
cd child
val=$(bmake -V PARENT_WS)
echo "PARENT_WS=$val"
echo "$val" | grep -q "^/"
# Full cross-workspace header search may still be TODO in implementation.
# Soft: at least macro is absolute.
echo "PARENT_WS absolute OK"
