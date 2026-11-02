#!/bin/sh
# mingw-test-path-has-runtime-req. bmake test of mingw-w64 output finds the
# mingw packages' DLLs, as bmake run does, with the sysroot's bin/ not on the
# caller's PATH and no project hook (OpenRider, 2026-11-02). Only for
# ABI=mingw on a Windows host; needs kyua and atf-sh.
set -eu
. "$BMK_TESTLIB"
[ "${ABI:-}" = mingw ] && [ "$BMK_T_OS" = win ] || exit 77
need_tool kyua "bmake test runs the tests through it"
need_tool atf-sh "the test is an atf-sh script"
bin=$(x86_64-w64-mingw32-gcc -print-sysroot)/mingw/bin
[ -f "$bin/libwinpthread-1.dll" ] || exit 77

mkdir -p ws/Fw/p.tst/testcases
printf 'PARENT_WS=\n.include "mk.workspace.mk"\n' > ws/makefile
printf 'PREREQS=\n.include <mk.framework.mk>\n' > ws/Fw/makefile
printf '.include <mk.tst.mk>\n' > ws/Fw/p.tst/makefile
cat > ws/Fw/p.tst/testcases/p.sh <<'EOF'
#!/usr/bin/env atf-sh
atf_test_case finds
finds_body() {
    IFS=:
    for d in $PATH; do
        [ ! -f "$d/libwinpthread-1.dll" ] || return 0
    done
    atf_fail "no mingw runtime DLL on PATH: $PATH"
}
atf_init_test_cases() { atf_add_test_case finds; }
EOF

# the caller's PATH, without the sysroot's bin/
clean=$(printf '%s' "$PATH" | tr ':' '\n' | grep -vx "$bin" | grep -v 'sys-root/mingw/bin' | paste -s -d: -)
cd ws
rc=0; env PATH="$clean" bmake test >test.log 2>&1 || rc=$?
[ $rc = 0 ] || { cat test.log >&2; echo "bmake test should have put the mingw sysroot's bin/ on PATH" >&2; exit 1; }
grep -q 'p.sh:finds  *->  *passed' test.log || { cat test.log >&2; exit 1; }

echo "mingw-test-path OK"
