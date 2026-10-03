#!/bin/sh
# test-rebuilds-module-library-req (lasviewer round 6, item 4): `bmake test`
# built the test programs but not the library they link, so after a source
# edit the tests ran against the OLD library and a test written to fail on
# the old code passed. Needs atf and kyua (skips, 77, without them).
set -eu
command -v kyua >/dev/null 2>&1 || exit 77
pkg-config --exists atf-c++ 2>/dev/null || exit 77

cd ws/Fw/libcnt.m
# The test expects the value the library returns NOW (1) -- passes.
bmake test >t1.log 2>&1

# Edit the library to return 2 and the test to expect 2, then run ONLY
# `bmake test` (no `bmake` first). Stale library => the test sees 1 and fails.
sleep 1
echo 'int cnt_value(void) { return 2; }' > src/cnt.cpp
sed -i.bak 's/#define EXPECTED 1/#define EXPECTED 2/' tests/cnt_test.cpp
if ! bmake test >t2.log 2>&1; then
    echo "bmake test ran against a stale library:" >&2
    tail -20 t2.log >&2
    exit 1
fi
echo "test-rebuilds-library OK"
