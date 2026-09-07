#!/bin/sh
set -eu
cd ws/Fw
out=$(bmake -V SUBDIR_MODULES 2>/dev/null || bmake -V SUBDIR)
echo "modules: $out"
echo "$out" | grep -q 'alpha.m'
echo "$out" | grep -q 'beta.m'
echo "$out" | grep -qv notamodule
