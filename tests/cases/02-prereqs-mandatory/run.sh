#!/bin/sh
set -eu
cd ws
# Building BadFw should fail because PREREQS is mandatory
if bmake -C BadFw all 2>err.log; then
    echo "expected failure for missing PREREQS" >&2
    exit 1
fi
grep -qi PREREQS err.log || grep -qi error err.log
echo "got expected error"
