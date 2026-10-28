#!/bin/sh
# test-rebuilds-module-library-req (lasviewer round 6, item 4): `bmake test`
# built the test programs but not the library they link, so after a source
# edit the tests ran against the OLD library and a test written to fail on
# the old code passed. Needs atf and kyua (skips, 77, without them).
set -eu
. "$BMK_TESTLIB"
if native_win_runtime; then echo "skip: no bmake test for a native Windows runtime (case 43 checks the refusal)" >&2; exit 77; fi
command -v kyua >/dev/null 2>&1 || exit 77
atf_pc --exists atf-c++ 2>/dev/null || exit 77
# An ATF C++ library built with another C++ runtime than this compiler's
# (FreeBSD packages: libc++; gcc: libstdc++) cannot be linked at all: skip.
case "${TOOLCHAIN:-}" in gcc) _cxx=g++ ;; *) _cxx=c++ ;; esac
_p=$(mktemp -d); printf '#include <atf-c++.hpp>\nATF_TEST_CASE(t); ATF_TEST_CASE_HEAD(t) {} ATF_TEST_CASE_BODY(t) {}\nATF_INIT_TEST_CASES(tcs) { ATF_ADD_TEST_CASE(tcs, t); }\n' > "$_p/p.cpp"
$_cxx $(atf_pc --cflags atf-c++) "$_p/p.cpp" $(atf_pc --libs atf-c++) -o "$_p/p" >/dev/null 2>&1 || { rm -rf "$_p"; exit 77; }
rm -rf "$_p"

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
