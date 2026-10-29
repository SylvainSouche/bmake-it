#!/bin/sh
# run-not-found-is-explained-req, run-keeps-caller-directory-req: OpenRider
# on FreeBSD (2026-10-29) -- the program built, two test modules did not
# link, so the framework was never copied up. `run PROGRAM=openrider` said
# "not found -- build first"; `run PROGRAM=sh` opened in the workspace root,
# whose bin lacked the program, and it looked deleted.
set -eu
. "$BMK_TESTLIB"
cd ws
rc=0; bmake >build.log 2>&1 || rc=$?
[ $rc != 0 ] || { echo "broken.m must fail the build" >&2; exit 1; }
# hello built, in its framework, but not copied up to the workspace.
[ -n "$(find Fw/build -path '*/bin/*' -name "$(prog_name hello)" | head -1)" ]
[ -z "$(find build -path '*/bin/*' -name "$(prog_name hello)" 2>/dev/null | head -1)" ]

# run says where it is and why it is not in the workspace bin.
if bmake run PROGRAM=hello >run1.log 2>&1; then
    echo "run of a program that was not copied up must fail" >&2; exit 1
fi
grep -q "error: hello not found in" run1.log
grep -q "it was built (Fw/build/.*/bin/hello" run1.log
grep -q "framework Fw's last build failed (modules: broken.m)" run1.log
grep -q "see Fw/build/.*/runs/latest/build.log" run1.log
if grep -q "build first" run1.log; then
    echo "a built program must not be reported as not built" >&2; exit 1
fi

# A program built nowhere still says build first.
if bmake run PROGRAM=nosuch-7c1e >run2.log 2>&1; then exit 1; fi
grep -q "not built anywhere in this workspace -- build first" run2.log

# run starts the program where it was typed, not in the workspace root.
ws=$(pwd -P)
[ "$(bmake run PROGRAM=sh ARGS='-c pwd\ -P')" = "$ws" ]
[ "$(cd Fw && bmake run PROGRAM=sh ARGS='-c pwd\ -P')" = "$ws/Fw" ]
[ "$(cd Fw/hello.m && bmake run PROGRAM=sh ARGS='-c pwd\ -P')" = "$ws/Fw/hello.m" ]

# tst-failure-does-not-block-copy-up-req: when only a test module fails,
# the framework is copied up all the same -- the build still fails.
rm -rf Fw/broken.m
mkdir -p Fw/broken.tst/src
printf 'PROG=brokenutil\n.include "mk.tst.mk"\n' > Fw/broken.tst/makefile
echo 'this is not C' > Fw/broken.tst/src/main.c
rc=0; bmake >build2.log 2>&1 || rc=$?
[ $rc != 0 ] || { echo "a failing test module must still fail the build" >&2; exit 1; }
grep -q "framework Fw: only test modules failed (broken.tst) -- its programs and libraries are copied up all the same" build2.log || {
    cat build2.log >&2; exit 1; }
[ "$(cd Fw && bmake run PROGRAM=hello)" = "hello from hello" ]

# Once everything builds, the build succeeds.
rm -rf Fw/broken.tst
bmake >build3.log 2>&1
[ "$(cd Fw && bmake run PROGRAM=hello)" = "hello from hello" ]

echo "run-after-failed-build OK"
