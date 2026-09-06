#!/bin/sh
set -eu
cd ws

if bmake install DESTDIR=/tmp/bmk-test-stage PREFIX=/usr/local 2>err.log; then
    echo "install should refuse on an unbuilt workspace" >&2
    exit 1
fi
cat err.log >&2
grep -qi "build first\|does not exist" err.log

echo "install-refuses-unbuilt OK"
