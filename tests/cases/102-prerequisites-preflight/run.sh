#!/bin/sh
# requires-preflight-req, module-skipped-after-failed-prereq-req. Found on
# FreeBSD (OpenRider, 2026-10-29): three missing packages showed as
# make-error noise in the middle of the build, then drowned in the compile
# errors of the modules that needed them. Now:
#   1. a workspace build lists EVERY missing prerequisite once -- a package,
#      a header, an import that does not resolve -- and builds nothing; the
#      same from a framework;
#   2. no pkg-config at all is said so, not reported as "not found";
#   3. a module whose prerequisite module failed is skipped, saying why,
#      and the workspace fails (no "bad number", no compile cascade).
set -eu
. "$BMK_TESTLIB"
ROOT=$(pwd)
mk() { mkdir -p "$(dirname "$1")"; printf "$2" > "$1"; }

# --- 1. one list, nothing built --------------------------------------------------
mk ws/Need/liba.m/makefile 'LIB=a\nREQUIRES=no-such-pkg-xyz123\n.include "mk.lib.mk"\n'
mk ws/Need/liba.m/src/a.c 'int a(void){return 1;}\n'
mk ws/Need/libh.m/makefile 'LIB=h\nREQUIRES=header:no_such_header_xyz.h\n.include "mk.lib.mk"\n'
mk ws/Need/libh.m/src/h.c 'int h(void){return 1;}\n'
mk ws/Need/libi.m/makefile 'LIB=i\nIMPORT=pkg:no-such-import-xyz\nIMPORT_HEADERS=x\n.include "mk.lib.mk"\n'
mk ws/Need/app.m/makefile 'PROG=app\nLIBS=a\n.include "mk.prog.mk"\n'
mk ws/Need/app.m/src/main.c 'int main(void){return 0;}\n'
cd ws
rc=0; bmake >need.log 2>&1 || rc=$?
[ $rc != 0 ] || { echo "a build with missing prerequisites must fail" >&2; exit 1; }
grep -q "missing prerequisites -- nothing was built" need.log || { cat need.log >&2; exit 1; }
grep -q "Need/liba.m: no-such-pkg-xyz123 -- not found by pkg-config" need.log
grep -q "Need/libh.m: header:no_such_header_xyz.h -- header not found" need.log
grep -q "Need/libi.m: pkg:no-such-import-xyz -- the import does not resolve" need.log
[ -z "$(find . -name '*.o')" ] || { echo "something was built:" >&2; find . -name '*.o' >&2; exit 1; }
if grep -qE "Unknown directive|bad number|in \.for loop" need.log; then
    echo "make noise in the report:" >&2; cat need.log >&2; exit 1
fi
rc=0; ( cd Need && bmake >../need-fw.log 2>&1 ) || rc=$?
[ $rc != 0 ] && grep -q "Need/liba.m: no-such-pkg-xyz123" need-fw.log

# --- 2. no pkg-config: said so -------------------------------------------------------
if command -v pkg-config >/dev/null 2>&1; then
    nopc="$ROOT/nopc"; mkdir -p "$nopc"
    # a PATH with every tool but pkg-config
    for d in $(echo "$PATH" | tr ':' ' '); do
        for f in "$d"/*; do
            # (every pkg-config: also x86_64-w64-mingw32-pkg-config, ABI=mingw's)
            n=${f##*/}; case "$n" in *pkg-config*|*pkgconf*) continue ;; esac
            [ -x "$f" ] && [ ! -e "$nopc/$n" ] && ln -s "$f" "$nopc/$n" 2>/dev/null || true
        done
    done
    rc=0; ( cd Need/liba.m && PATH="$nopc" bmake >../../nopc.log 2>&1 ) || rc=$?
    [ $rc != 0 ] || { echo "the build should fail without pkg-config" >&2; exit 1; }
    # (ABI=mingw names the mingw-w64 pkg-config it needs instead)
    grep -qE "pkg-config is not installed|no pkg-config for .* output: .*pkg-config is not on PATH" nopc.log || { echo "no pkg-config must be said so:" >&2; cat nopc.log >&2; exit 1; }
fi
rm -rf Need

# --- 3. a failing module and its dependent -------------------------------------------
mk Brk/makefile 'PREREQS=\n.include "mk.framework.mk"\n'
mk Brk/libbroken.m/makefile 'LIB=broken\n.include "mk.lib.mk"\n'
mk Brk/libbroken.m/src/b.c 'int broken(void){ return }\n'
mk Brk/user.m/makefile 'PROG=user\nLIBS=broken\n.include "mk.prog.mk"\n'
mk Brk/user.m/src/main.c 'int broken(void); int main(void){return broken();}\n'
rc=0; bmake >brk.log 2>&1 || rc=$?
[ $rc != 0 ] || { echo "a failing module must fail the workspace" >&2; cat brk.log >&2; exit 1; }
grep -q "module user.m skipped: prerequisite module libbroken.m failed" brk.log || { cat brk.log >&2; exit 1; }
grep -q "user.m -- skipped: its prerequisite libbroken.m failed" brk.log
grep -q "workspace BUILD FAILED: Brk" brk.log
! grep -q "workspace build complete" brk.log
! grep -qE "bad number|Unknown directive" brk.log
! grep -q "main.c" brk.log   # user.m was never compiled
rm -rf Brk

# --- 4. a .tst module's ATF is in the list too (atf-runtime-only-is-named-req) -------
# FreeBSD (2026-10-29): FreeBSD-atf (the base system's run-time part) but not
# the atf package -- reported only once the build reached the test modules,
# and only as "not found". The probe's answer is forced from the command
# line, so this runs whether or not ATF is installed here.
if ! atf_bundled; then
    mk Tst/makefile 'PREREQS=\n.include "mk.framework.mk"\n'
    mk Tst/hello.m/makefile 'PROG=hello\n.include "mk.prog.mk"\n'
    mk Tst/hello.m/src/main.c 'int main(void){return 0;}\n'
    mk Tst/t.tst/makefile 'TEST_PROG=t_test\n.include "mk.tst.mk"\n'
    mk Tst/t.tst/src/t_test.cpp '#include <atf-c++.hpp>\nATF_INIT_TEST_CASES(tcs) {}\n'
    rc=0; bmake '_ATF_FOUND_CMD=echo runtime=/fake/lib/libatf-c++.so.2' >atfrt.log 2>&1 || rc=$?
    [ $rc != 0 ] || { echo "a missing ATF must fail the build" >&2; cat atfrt.log >&2; exit 1; }
    grep -q "missing prerequisites -- nothing was built" atfrt.log || { cat atfrt.log >&2; exit 1; }
    grep -q "Tst/t.tst: atf-c++ -- ATF library for this test module: only its run-time library is installed (/fake/lib/libatf-c++.so.2)" atfrt.log
    grep -q "FreeBSD-atf" atfrt.log
    [ -z "$(find . -name '*.o')" ] || { echo "something was built:" >&2; find . -name '*.o' >&2; exit 1; }
    rc=0; bmake '_ATF_FOUND_CMD=echo no' >atfno.log 2>&1 || rc=$?
    [ $rc != 0 ] && grep -q "Tst/t.tst: atf-c++ -- ATF library for this test module: no .pc file" atfno.log || {
        echo "ATF not found at all must be listed:" >&2; cat atfno.log >&2; exit 1; }
    # A build of the module alone stops on it, with the same explanation.
    rc=0; ( cd Tst/t.tst && bmake '_ATF_FOUND_CMD=echo runtime=/fake/lib/libatf-c++.so.2' ) >atfmod.log 2>&1 || rc=$?
    [ $rc != 0 ] && grep -q "atf-c++ is only installed as a run-time library (/fake/lib/libatf-c++.so.2)" atfmod.log || {
        echo "the module build must explain a run-time-only ATF:" >&2; cat atfmod.log >&2; exit 1; }
fi

echo "prerequisites-preflight OK"
