#!/bin/sh
# scripts-only-tst-reads-hooks-req. A .tst module with neither PROG= nor
# TEST_PROG= reads the mk/ hooks, pre and local, the same cascade as any other
# module (workspace, framework, its own), with the conditional names too. It
# read none, so a hook setting up the tests' environment did not reach it
# (OpenRider, 2026-11-02). Needs no kyua: nothing is run.
set -eu
. "$BMK_TESTLIB"

mkdir -p ws/mk ws/Fw/mk ws/Fw/s.tst/mk ws/Fw/s.tst/testcases
printf 'PARENT_WS=\n.include "mk.workspace.mk"\n' > ws/makefile
printf 'PREREQS=\n.include <mk.framework.mk>\n' > ws/Fw/makefile
printf '.include <mk.tst.mk>\n' > ws/Fw/s.tst/makefile
printf '#!/usr/bin/env atf-sh\natf_test_case t\nt_body() { :; }\natf_init_test_cases() { atf_add_test_case t; }\n' > ws/Fw/s.tst/testcases/s.sh

printf 'SEEN += ws-pre\n'   > ws/mk/pre.mk
printf 'SEEN += fw-pre\n'   > ws/Fw/mk/pre.mk
printf 'SEEN += mod-pre\n'  > ws/Fw/s.tst/mk/pre.mk
printf 'SEEN += ws-local\n' > ws/mk/local.mk
printf 'SEEN += mod-local\nhooked:\n\t@echo hook target ran\n' > ws/Fw/s.tst/mk/local.mk

cd ws/Fw/s.tst
tc=$(bmake -V TOOLCHAIN)
printf 'SEEN += mod-pre-toolchain\n' > "mk/pre.$tc.mk"

want='ws-pre fw-pre mod-pre mod-pre-toolchain ws-local mod-local'
got=$(bmake -V '${SEEN}')
[ "$got" = "$want" ] || { echo "hooks read: expected [$want], got [$got]" >&2; exit 1; }

bmake hooked >hooked.log 2>&1 || { cat hooked.log >&2; echo "a target from a local hook should run" >&2; exit 1; }
grep -q 'hook target ran' hooked.log

# ... and a plain build from the workspace still works
cd ../..
bmake >build.log 2>&1 || { cat build.log >&2; exit 1; }

echo "tst-scripts-only-hooks OK"
