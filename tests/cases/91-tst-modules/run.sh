#!/bin/sh
# tst-module-layout-req, tst-scripts-are-tests-req, tst-test-prog-req,
# tst-test-srcs-req, tst-test-environment-req: .tst test modules.
#   geo.tst     TEST_PROG= only, linked against the framework's library
#   tools.tst   PROG= (utility) + TEST_PROG= + TEST_SRCS= + testcases/*.sh
#   render.tst  scripts only
# Needs atf and kyua (skips, 77, without them).
set -eu
command -v kyua >/dev/null 2>&1 || exit 77
pkg-config --exists atf-c++ 2>/dev/null || exit 77
cd ws

# --- .tst modules are BUILT by a plain bmake, but never shipped --------------------
bmake >build.log 2>&1
[ -x Fw/geo.tst/build/*/bin/geo_test ] 2>/dev/null || ls Fw/geo.tst/build/*/bin/geo_test >/dev/null
ls Fw/tools.tst/build/*/bin/tool Fw/tools.tst/build/*/bin/tool_test >/dev/null
grep -q "===> building module geo.tst" build.log
grep -q "===> building module tools.tst" build.log
grep -q "===> built test program tool_test" build.log
# ... but never copied up into the framework's or workspace's bin/lib.
[ -z "$(find Fw/build build -path '*/bin/*' \( -name geo_test -o -name tool -o -name tool_test \) 2>/dev/null | head -1)" ] || {
    echo "a .tst module's program was shipped into bin/" >&2; exit 1; }

# A compile error in a test surfaces at BUILD time, not only under `bmake test`.
# (bmake compares mtimes at one-second granularity on some hosts: pause so the
# edit is newer than the build that just ran.)
sleep 1
cp Fw/tools.tst/src/tool_test.cpp Fw/tools.tst/src/tool_test.cpp.keep
echo 'this is not C++' >> Fw/tools.tst/src/tool_test.cpp
rc=0; bmake >build_bad.log 2>&1 || rc=$?
[ $rc != 0 ] || { echo "a test's compile error must fail a plain bmake" >&2; exit 1; }
sleep 1
mv Fw/tools.tst/src/tool_test.cpp.keep Fw/tools.tst/src/tool_test.cpp
bmake >/dev/null 2>&1

# --- bmake test builds and runs them -----------------------------------------
bmake test >test1.log 2>&1 || { echo "bmake test failed" >&2; tail -20 test1.log >&2; exit 1; }
grep -q "geo_test:value  *->  *passed" test1.log
grep -q "tool_test:utility_is_reachable  *->  *passed" test1.log
grep -q "run.sh:uses_utility  *->  *passed" test1.log        # the utility, by name
grep -q "run.sh:sees_framework_bin  *->  *passed" test1.log   # another module's program on PATH
grep -q "run.sh:sees_shared_data  *->  *passed" test1.log     # BMK_SHAREDIR
grep -q "ok.sh:fine  *->  *passed" test1.log                  # scripts-only module
# The utility is built and staged but NOT registered as a test.
! grep -q "tool:" test1.log

# --- TEST= selects one test by name -----------------------------------------------
bmake test TEST=ok.sh >test2.log 2>&1
grep -q "ok.sh:fine  *->  *passed" test2.log
! grep -q "geo_test\|tool_test\|uses_utility" test2.log

# --- a failing script fails the build ------------------------------------------------
cat > Fw/render.tst/testcases/bad.sh <<'XEOF'
#!/usr/bin/env atf-sh
atf_test_case broken
broken_body() { atf_fail "deliberately failing"; }
atf_init_test_cases() { atf_add_test_case broken; }
XEOF
rc=0; bmake test >test3.log 2>&1 || rc=$?
[ $rc != 0 ] || { echo "a failing .tst script must fail bmake test" >&2; exit 1; }
grep -q "bad.sh:broken  *->  *failed" test3.log
rm -f Fw/render.tst/testcases/bad.sh

# --- PROG= and TEST_PROG= together need TEST_SRCS= ------------------------------------
cp Fw/tools.tst/makefile Fw/tools.tst/makefile.keep
printf 'PROG=tool\nTEST_PROG=tool_test\n.include <mk.tst.mk>\n' > Fw/tools.tst/makefile
rc=0; ( cd Fw/tools.tst && bmake test >../../err.log 2>&1 ) || rc=$?
[ $rc != 0 ] && grep -q "TEST_SRCS= must name the test program's sources" err.log || {
    echo "PROG= + TEST_PROG= without TEST_SRCS= must be an error" >&2; cat err.log >&2; exit 1; }
mv Fw/tools.tst/makefile.keep Fw/tools.tst/makefile

# --- an excluded .tst module is skipped like any other -----------------------------
OS=$(bmake -V '${TARGET}')
printf 'PLATFORMS=-%s\n.include <mk.tst.mk>\n' "$OS" > Fw/render.tst/makefile
bmake test >test4.log 2>&1 || { echo "an excluded .tst module must not fail the run" >&2; tail -8 test4.log >&2; exit 1; }
! grep -q "ok.sh:fine" test4.log

echo "tst-modules OK"
