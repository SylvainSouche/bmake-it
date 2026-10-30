#!/bin/sh
# cross-test-runner-req, cross-test-needs-runner-req, cross-test-ships-dependencies-req.
# A "pretend target": a cmd: runner that runs the staged tests with the build
# host's library directories HIDDEN, so the only libgeo the program under test
# can load is the copy bmake test shipped (not on macOS: SIP strips DYLD_*). A control proves the hiding works
# (the program cannot start without the shipped copy). Needs kyua and atf-sh
# (skips, 77, without them).
set -eu
. "$BMK_TESTLIB"
command -v kyua >/dev/null 2>&1 || exit 77
command -v atf-sh >/dev/null 2>&1 || exit 77
ROOT=$(pwd)

cat > "$ROOT/runner.sh" <<RUNNER
#!/bin/sh
# cmd: runner. \$1 = the staged directory. Hides the host's library directories,
# runs run.sh there as the target would, and puts them back.
set -u
stage=\$1
hid=""
for d in $ROOT/ws/Fw/build/*/lib $ROOT/ws/Fw/libgeo.m/build/*/lib $ROOT/ws/build/*/lib; do
    [ -d "\$d" ] || continue
    # macOS strips DYLD_* through /bin/sh and /usr/bin/env (SIP), so a shipped
    # library cannot be found there: do not pretend to test it (documented limit)
    [ "\$(uname -s)" != Darwin ] || continue
    mv "\$d" "\$d.hidden"; hid="\$hid \$d"
done
restore() { for d in \$hid; do mv "\$d.hidden" "\$d"; done; }
trap restore EXIT
echo "\$hid" > $ROOT/hidden.list
# control: without the shipped copy the program cannot even start
if [ "\$(uname -s)" != Darwin ] && $ROOT/ws/Fw/tools.tst/build/*/bin/tool >/dev/null 2>&1; then
    echo "hiding the library directories had no effect" > $ROOT/control-failed
fi
sh "\$stage/run.sh" "\$stage"
RUNNER
chmod +x "$ROOT/runner.sh"

cd ws
bmake >build.log 2>&1 || { cat build.log >&2; exit 1; }
ls Fw/tools.tst/build/*/bin/tool >/dev/null

# --- 1. TEST_RUNNER=cmd: runs the tests through the runner, with shipped libs ---
bmake test TEST_RUNNER=cmd:$ROOT/runner.sh >test1.log 2>&1 || { cat test1.log >&2; echo "bmake test via the runner failed" >&2; exit 1; }
grep -q "running the tests on cmd:" test1.log
grep -q "run.sh:uses_tool_and_its_library  *->  *passed" test1.log   # the shipped libgeo was loaded
grep -q "run.sh:sees_shared_data  *->  *passed" test1.log             # BMK_SHAREDIR shipped
if [ "$(uname -s)" != Darwin ]; then
    [ "$(tr -d ' \n' < "$ROOT/hidden.list")" != "" ] \
        || { echo "the runner hid no library directory (setup)" >&2; exit 1; }
fi
[ ! -e "$ROOT/control-failed" ] || { cat "$ROOT/control-failed" >&2; exit 1; }
# the reports came back to the usual place
ls Fw/tools.tst/build/*/runs/latest/test-results.xml >/dev/null
grep -q "uses_tool_and_its_library" Fw/tools.tst/build/*/runs/latest/test-results.xml
# the host's directories were put back
ls -d Fw/build/*/lib >/dev/null

# --- 2. a failing test fails bmake test, with the report still written -----------
cat > Fw/tools.tst/testcases/bad.sh <<'XEOF'
#!/usr/bin/env atf-sh
atf_test_case broken
broken_body() { atf_fail "deliberately failing"; }
atf_init_test_cases() { atf_add_test_case broken; }
XEOF
rc=0; bmake test TEST_RUNNER=cmd:$ROOT/runner.sh >test2.log 2>&1 || rc=$?
[ $rc != 0 ] || { echo "a failing test on the runner must fail bmake test" >&2; exit 1; }
grep -q "bad.sh:broken  *->  *failed" test2.log
grep -qE '<(failure|error)' Fw/tools.tst/build/*/runs/latest/test-results.xml
rm -f Fw/tools.tst/testcases/bad.sh

# --- 3. TEST_RUNNER.<os>-<arch> wins over TEST_RUNNER ---------------------------------
key=$(cd Fw/tools.tst && bmake -V '${TARGET}')-$(cd Fw/tools.tst && bmake -V '${TARGET_ARCH}')
bmake test TEST_RUNNER=local "TEST_RUNNER.$key=cmd:$ROOT/runner.sh" >test3.log 2>&1 \
    || { cat test3.log >&2; echo "the per-target runner should have been used" >&2; exit 1; }
grep -q "running the tests on cmd:" test3.log
# ... and TEST_RUNNER=local alone runs here, as before
bmake test TEST_RUNNER=local >test4.log 2>&1
! grep -q "running the tests on" test4.log
grep -q "run.sh:uses_tool_and_its_library  *->  *passed" test4.log

# --- 4. a foreign target with no runner stops, before building, naming what to set ---
case "$(uname -s)" in FreeBSD) fo=netbsd; sv=BMK_NETBSD_SYSROOT ;; *) fo=freebsd; sv=BMK_FREEBSD_SYSROOT ;; esac
mkdir -p "$ROOT/fakesysroot"
# (MSVC and mingw are Windows ABIs: the cross target takes the default toolchain)
xenv=""; if native_win_runtime; then xenv="-u ABI -u TOOLCHAIN"; fi
rc=0; env $xenv "$sv=$ROOT/fakesysroot" bmake test TARGET=$fo >test5.log 2>&1 || rc=$?
[ $rc != 0 ] || { echo "a foreign target without a runner must fail" >&2; exit 1; }
grep -q "TEST_RUNNER\.$fo-" test5.log || { cat test5.log >&2; echo "the error should name TEST_RUNNER.<os>-<arch>" >&2; exit 1; }
grep -q "TEST_RUNNER=local" test5.log
! grep -q "building test\|===> built" test5.log

echo "cross-test-runner OK"
