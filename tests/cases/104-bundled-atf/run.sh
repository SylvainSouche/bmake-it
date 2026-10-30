#!/bin/sh
# native-windows-tests-req, bundled-atf-selectable-req (atf-for-windows-
# dec): the same ATF test sources build and run against the installed ATF
# and against the ATF Bmake It carries (contrib/) -- BMK_ATF=bundled on
# every target, always for a native Windows runtime (ABI=mingw,
# TOOLCHAIN=msvc), which the Cygwin Kyua runs. What the Windows build does
# not cover yet (atf_utils_fork) fails the test case saying so, there only.
# Needs kyua; the installed-ATF run also needs atf (else only bundled).
set -eu
. "$BMK_TESTLIB"
need_tool kyua "bmake test runs the tests through it"
ROOT=$(pwd)

# run_with <name> [VAR=value...]: build and test a fresh copy of ws/
run_with() {
    name=$1; shift
    rm -rf "$ROOT/$name"; cp -r "$ROOT/ws" "$ROOT/$name"; cd "$ROOT/$name"

    # --- a plain build: the .tst test program links ATF ------------------------
    env "$@" bmake >build.log 2>&1 || { echo "[$name] the build failed:" >&2; tail -20 build.log >&2; exit 1; }
    if [ "$name" != installed ]; then
        # built from contrib/ once for the framework's build root, at the
        # first module that needs it
        [ "$(grep -c '===> building ATF 0.23 ' build.log)" = 1 ] || {
            echo "[$name] the ATF Bmake It carries should have been built exactly once:" >&2; cat build.log >&2; exit 1; }
        ls Fw/build/*/atf/stamp >/dev/null
    else
        ! grep -q '===> building ATF' build.log
    fi

    # --- bmake test: the same results everywhere -------------------------------
    rc=0; env "$@" bmake test >test.log 2>&1 || rc=$?
    for r in 'calc_ctest:adds  ->  passed' 'calc_ctest:files  ->  passed' \
             'calc_ctest:skipped  ->  skipped: on purpose' \
             'calc_ctest:known_bug  ->  expected_failure: calc_add is not multiplication' \
             'calc_test:adds  ->  passed' 'calc_test:files  ->  passed' 'calc_test:config  ->  passed' \
             'sum_test:sums  ->  passed'; do
        grep -q "$r" test.log || { echo "[$name] missing from the results: $r" >&2; cat test.log >&2; exit 1; }
    done
    # (built by the plain build above: not again)
    ! grep -q '===> building ATF' test.log
    if native_win_runtime; then
        grep -q "calc_ctest:child  ->  failed: atf_utils_fork is not available in Bmake It's ATF for native Windows runtimes" test.log || {
            echo "[$name] an ATF feature not ported to Windows must fail its test case saying so:" >&2; cat test.log >&2; exit 1; }
        [ $rc != 0 ] || { echo "[$name] a failed test case must fail bmake test" >&2; exit 1; }
    else
        grep -q 'calc_ctest:child  ->  passed' test.log
        [ $rc = 0 ] || { echo "[$name] bmake test failed:" >&2; tail -20 test.log >&2; exit 1; }
    fi

    # --- a failing check fails bmake test, with ATF's message ------------------
    sleep 1
    sed -i.bak 's/ATF_REQUIRE_EQ(5, calc_add(2, 3))/ATF_REQUIRE_EQ(6, calc_add(2, 3))/' Fw/libcalc.m/tests/calc_test.cpp
    rc=0; env "$@" bmake test >test2.log 2>&1 || rc=$?
    [ $rc != 0 ] || { echo "[$name] a failing check must fail bmake test" >&2; exit 1; }
    grep -q 'calc_test:adds  ->  failed: .*6 != calc_add(2, 3)' test2.log || {
        echo "[$name] the failing check should be reported with ATF's message:" >&2; cat test2.log >&2; exit 1; }
    cd "$ROOT"
}

if native_win_runtime; then
    run_with native-win
    echo "bundled-atf OK (native Windows runtime)"
    exit 0
fi

# The installed ATF, when there is one this compiler can link.
ran=bundled
if atf_pc --exists atf-c 2>/dev/null && atf_pc --exists atf-c++ 2>/dev/null; then
    # An ATF C++ library built with another C++ runtime than this compiler's
    # (FreeBSD packages: libc++; gcc: libstdc++) cannot be linked at all.
    case "${TOOLCHAIN:-}" in gcc) _cxx=g++ ;; *) _cxx=c++ ;; esac
    _p=$(mktemp -d); printf '#include <atf-c++.hpp>\nATF_TEST_CASE(t); ATF_TEST_CASE_HEAD(t) {} ATF_TEST_CASE_BODY(t) {}\nATF_INIT_TEST_CASES(tcs) { ATF_ADD_TEST_CASE(tcs, t); }\n' > "$_p/p.cpp"
    if $_cxx $(atf_pc --cflags atf-c++) "$_p/p.cpp" $(atf_pc --libs atf-c++) -o "$_p/p" >/dev/null 2>&1; then
        run_with installed BMK_ATF=installed
        ran="installed and bundled"
    fi
    rm -rf "$_p"
fi
# The ATF Bmake It carries, on this target too.
run_with bundled BMK_ATF=bundled

# A misspelt BMK_ATF is an error, not the default.
rc=0; ( cd ws && bmake BMK_ATF=bundeld >../bad.log 2>&1 ) || rc=$?
[ $rc != 0 ] && grep -q 'BMK_ATF=bundeld: expected bundled' bad.log || {
    echo "a misspelt BMK_ATF must be an error:" >&2; cat bad.log >&2; exit 1; }

echo "bundled-atf OK ($ran)"
