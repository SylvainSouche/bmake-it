#!/bin/sh
# path-characters-supported-req: the features beyond a plain build keep working in
# a directory whose name has a space, parentheses, an apostrophe, an ampersand and a
# hash sign in it (case 116 covers build, install and clean for every character).
# Each part is a separate tree under SP:
#   A  a prerequisite framework in a PARENT_WS workspace, the parent written the
#      way a user writes it (a backslash before a space, an apostrophe, a hash)
#   B  IMPORT= resolved by <NAME>_PREFIX, headers staged, library linked
#   C  IMPORT=fetch: with a patch, the file:// URL written percent-encoded
#   D  FETCH_BUILD=cmake (CMake's own makefiles cannot have a # in the path: a
#      directory without one)
#   E  add-prereq and add-parent write the form a user writes, bmake run, bmake
#      test (a compiled ATF test), bmake docs
set -eu
. "$BMK_TESTLIB"
. "$BMK_MKDIR/../scripts/bmk-names.sh"
TOP=$(pwd)
SP="$TOP/sp dir (1) & co's #x"
mkdir -p "$SP"
fail() { echo "FAIL: $*" >&2; exit 1; }
runs() { # runs <bin> -> its output
    with_libdir "$(prog_libdir "$1")" "$1"
}
sha256() { (sha256sum "$1" 2>/dev/null || shasum -a 256 "$1" 2>/dev/null) | awk '{print $1}'; }

# --- A ----------------------------------------------------------------------
A="$SP/A"
mkdir -p "$A/parent/Lib/libspfutil.m/src" "$A/parent/Lib/include" "$A/child/App/app.m/src"
printf 'PARENT_WS=\n.include <mk.workspace.mk>\n' > "$A/parent/makefile"
printf 'PREREQS=\n.include <mk.framework.mk>\n' > "$A/parent/Lib/makefile"
printf 'LIB=spfutil\nLIB_SHARED=YES\nSHLIB_MAJOR=1\n.include <mk.lib.mk>\n' > "$A/parent/Lib/libspfutil.m/makefile"
printf 'int util(void);\n' > "$A/parent/Lib/include/util.h"
printf '#include "util.h"\nint util(void) { return 7; }\n' > "$A/parent/Lib/libspfutil.m/src/u.c"
printf 'PARENT_WS=%s\n.include <mk.workspace.mk>\n' "$(bmk_wl "$A/parent")" > "$A/child/makefile"
printf 'PREREQS=Lib\n.include <mk.framework.mk>\n' > "$A/child/App/makefile"
printf 'PROG=app\nLIBS=spfutil\n.include <mk.prog.mk>\n' > "$A/child/App/app.m/makefile"
printf '#include <stdio.h>\n#include "util.h"\nint main(void) { printf("%%d\\n", util()); return 0; }\n' > "$A/child/App/app.m/src/main.c"
( cd "$A/parent" && bmake >build.log 2>&1 ) || { cat "$A/parent/build.log" >&2; fail "A: the parent workspace did not build"; }
( cd "$A/child" && bmake >build.log 2>&1 ) || { tail -20 "$A/child/build.log" >&2; fail "A: the child did not build against its parent workspace"; }
if grep -q 'PARENT_WS entry does not exist' "$A/child/build.log"; then fail "A: the parent workspace path was read as several"; fi
bin=$(find "$A/child/App" -type f -name "$(prog_name app)" | head -1)
[ -n "$bin" ] || fail "A: no program"
# Windows has no run path: the parent's DLL is found through PATH
_dll=$(find "$A/parent" -type f -name '*spfutil*.dll' | head -1)
( [ -z "$_dll" ] || PATH="$(dirname "$_dll"):$PATH"
  [ "$(runs "$bin")" = 7 ] ) || fail "A: the program did not run against the parent's library"
( cd "$A/child" && bmake clean >/dev/null 2>&1 )
[ -z "$(find "$A/child" -type f -name "$(prog_name app)" -path '*/bin/*')" ] || fail "A: clean left the program"

# --- B ----------------------------------------------------------------------
B="$SP/B"
mkdir -p "$B/ws/Fw/libgreet2.m" "$B/ws/Fw/app.m/src" "$B/fake/pkg/include/greet2" "$B/fake/pkg/lib" "$B/fake/src"
printf 'PARENT_WS=\n.include <mk.workspace.mk>\n' > "$B/ws/makefile"
printf 'PREREQS=\n.include <mk.framework.mk>\n' > "$B/ws/Fw/makefile"
printf 'LIB=greet2\nIMPORT=pkg:greet2\nIMPORT_HEADERS=greet2\n.include <mk.lib.mk>\n' > "$B/ws/Fw/libgreet2.m/makefile"
printf 'PROG=app\nLIBS=greet2\n.include <mk.prog.mk>\n' > "$B/ws/Fw/app.m/makefile"
printf '#include <stdio.h>\n#include "greet2/api.h"\nint main(void){ printf("%%s\\n", greet2_value); return 0; }\n' > "$B/ws/Fw/app.m/src/main.c"
echo 'const char *greet2_value = "hello from a prefix import";' > "$B/fake/src/impl.c"
printf '#pragma once\nextern const char *greet2_value;\n' > "$B/fake/pkg/include/greet2/api.h"
"${CC:-cc}" -c "$B/fake/src/impl.c" -o "$B/fake/src/impl.o"
fake_ar "$B/fake/pkg/lib/libgreet2.a" "$B/fake/src/impl.o"
( cd "$B/ws" && GREET2_PREFIX="$B/fake/pkg" bmake >build.log 2>&1 ) || { tail -20 "$B/ws/build.log" >&2; fail "B: the import did not build"; }
bin=$(find "$B/ws" -type f -name "$(prog_name app)" | head -1)
[ "$(runs "$bin")" = "hello from a prefix import" ] || fail "B: the imported library was not linked"
( cd "$B/ws" && GREET2_PREFIX="$B/fake/pkg" bmake >build2.log 2>&1 ) || fail "B: the second build failed"

# --- C ----------------------------------------------------------------------
C="$SP/C"
mkdir -p "$C/fake/upstream/fakelib-1.0" "$C/fake/dist" "$C/fake/patched/fakelib-1.0" "$C/ws/Fw/app.m/src" "$C/ws/Fw/libfakelib.m/patches"
printf 'const char *fakelib_greet(void);\n' > "$C/fake/upstream/fakelib-1.0/greet.h"
printf '#include "greet.h"\nconst char *fakelib_greet(void) {\n    return "hello original";\n}\n' > "$C/fake/upstream/fakelib-1.0/greet.c"
printf '#include "greet.h"\nconst char *fakelib_greet(void) {\n    return "hello patched";\n}\n' > "$C/fake/patched/fakelib-1.0/greet.c"
( cd "$C/fake/upstream" && tar czf "$C/fake/dist/fakelib-1.0.tar.gz" fakelib-1.0 )
diff -u -L a/greet.c -L b/greet.c "$C/fake/upstream/fakelib-1.0/greet.c" "$C/fake/patched/fakelib-1.0/greet.c" \
    > "$C/ws/Fw/libfakelib.m/patches/fix.patch" || true
echo "SHA256 (fakelib-1.0.tar.gz) = $(sha256 "$C/fake/dist/fakelib-1.0.tar.gz")" > "$C/ws/Fw/libfakelib.m/distinfo"
printf 'PARENT_WS=\n.include <mk.workspace.mk>\n' > "$C/ws/makefile"
printf 'PREREQS=\n.include <mk.framework.mk>\n' > "$C/ws/Fw/makefile"
# (FETCH_URL= is a list of URLs, so the path in a file:// URL is percent-encoded)
printf 'LIB=fakelib\nIMPORT=fetch:fakelib\nFETCH_URL=file://%s/fakelib-1.0.tar.gz\nFETCH_PATCHES=fix.patch\nSRCS=greet.c\nIMPORT_HEADERS=greet.h\n.include <mk.lib.mk>\n' \
    "$(bmk_enc "$C/fake/dist")" > "$C/ws/Fw/libfakelib.m/makefile"
printf 'PROG=app\nLIBS=fakelib\n.include <mk.prog.mk>\n' > "$C/ws/Fw/app.m/makefile"
printf '#include <stdio.h>\n#include "greet.h"\nint main(void){ puts(fakelib_greet()); return 0; }\n' > "$C/ws/Fw/app.m/src/main.c"
( cd "$C/ws" && bmake >build.log 2>&1 ) || { tail -20 "$C/ws/build.log" >&2; fail "C: the fetched import did not build"; }
grep -q "verified fakelib-1.0.tar.gz (sha256 ok)" "$C/ws/build.log" || fail "C: the distfile was not verified"
bin=$(find "$C/ws" -type f -name "$(prog_name app)" | head -1)
[ "$(runs "$bin")" = "hello patched" ] || fail "C: the patch was not applied, or the library not linked"

# --- D ----------------------------------------------------------------------
# (on a BSD the generated makefiles are read by the BSD make, which cannot take such
# paths in them: that is CMake's and make's, not ours)
case $(uname -s) in FreeBSD|NetBSD|OpenBSD|DragonFly) _bsd=yes ;; *) _bsd=no ;; esac
if command -v cmake >/dev/null 2>&1 && [ "$_bsd" = no ]; then
    D="$TOP/sp dir (1) & co's x"
    mkdir -p "$D/fake/upstream/foo-1.0" "$D/fake/dist" "$D/ws/Fw/app.m/src" "$D/ws/Fw/libfoo.m"
    printf 'cmake_minimum_required(VERSION 3.10)\nproject(foo C)\nadd_library(foo SHARED foo.c)\ninstall(TARGETS foo DESTINATION lib)\ninstall(FILES foo.h DESTINATION include)\n' > "$D/fake/upstream/foo-1.0/CMakeLists.txt"
    printf '#ifndef FOO_H\n#define FOO_H\nconst char *foo_greet(void);\n#endif\n' > "$D/fake/upstream/foo-1.0/foo.h"
    printf '#include "foo.h"\nconst char *foo_greet(void) { return "hello cmake"; }\n' > "$D/fake/upstream/foo-1.0/foo.c"
    ( cd "$D/fake/upstream" && tar czf "$D/fake/dist/foo-1.0.tar.gz" foo-1.0 )
    echo "SHA256 (foo-1.0.tar.gz) = $(sha256 "$D/fake/dist/foo-1.0.tar.gz")" > "$D/ws/Fw/libfoo.m/distinfo"
    printf 'PARENT_WS=\n.include <mk.workspace.mk>\n' > "$D/ws/makefile"
    printf 'PREREQS=\n.include <mk.framework.mk>\n' > "$D/ws/Fw/makefile"
    printf 'LIB=foo\nIMPORT=fetch:foo\nFETCH_URL=file://%s/foo-1.0.tar.gz\nFETCH_BUILD=cmake\nIMPORT_HEADERS=foo.h\n.include <mk.lib.mk>\n' \
        "$(bmk_enc "$D/fake/dist")" > "$D/ws/Fw/libfoo.m/makefile"
    printf 'PROG=app\nLIBS=foo\n.include <mk.prog.mk>\n' > "$D/ws/Fw/app.m/makefile"
    printf '#include <stdio.h>\n#include "foo.h"\nint main(void){ puts(foo_greet()); return 0; }\n' > "$D/ws/Fw/app.m/src/main.c"
    ( cd "$D/ws" && bmake >build.log 2>&1 ) || { tail -20 "$D/ws/build.log" >&2; fail "D: the cmake build did not work"; }
    bin=$(find "$D/ws" -type f -name "$(prog_name app)" | head -1)
    [ "$(runs "$bin")" = "hello cmake" ] || fail "D: the cmake-built library was not linked"
    ( cd "$D/ws/Fw/libfoo.m" && bmake all >build2.log 2>&1 ) || { cat "$D/ws/Fw/libfoo.m/build2.log" >&2; fail "D: the second build failed"; }
    if grep -q "FETCH_BUILD=cmake: configure" "$D/ws/Fw/libfoo.m/build2.log"; then fail "D: the unchanged second build ran cmake again"; fi
    rm -rf "$D"
else
    echo "D skipped: no cmake, or a BSD make" >&2
fi

# --- E ----------------------------------------------------------------------
E="$SP/E"
mkdir -p "$E/ws/Lib/libmath.m/src" "$E/ws/Lib/include" "$E/ws/App/app.m/src" "$E/ws/Lib/math.tst/src"
printf 'PARENT_WS=\n.include <mk.workspace.mk>\n' > "$E/ws/makefile"
printf 'PREREQS=\n.include <mk.framework.mk>\n' > "$E/ws/Lib/makefile"
printf 'PREREQS=Lib\n.include <mk.framework.mk>\n' > "$E/ws/App/makefile"
printf 'LIB=math\n.include <mk.lib.mk>\n' > "$E/ws/Lib/libmath.m/makefile"
printf '/** Doubles its argument. */\nint dbl(int x);\n' > "$E/ws/Lib/include/math.h"
printf '#include "math.h"\nint dbl(int x) { return 2 * x; }\n' > "$E/ws/Lib/libmath.m/src/m.c"
printf 'PROG=app\nLIBS=math\n.include <mk.prog.mk>\n' > "$E/ws/App/app.m/makefile"
printf '#include <stdio.h>\n#include "math.h"\nint main(void){ printf("%%d\\n", dbl(21)); return 0; }\n' > "$E/ws/App/app.m/src/main.c"
cd "$E/ws"
# add-prereq / add-parent write the form a user writes (a backslash), and it reads back
( cd App && bmake add-prereq FW="X Y's #z" >/dev/null 2>&1 )
grep -q '^PREREQS=Lib X\\ Y\\'"'"'s\\ \\#z$' App/makefile || { cat App/makefile >&2; fail "E: add-prereq wrote the wrong form"; }
bmake add-parent WS="$SP/other (1)" >/dev/null 2>&1
grep -q '^PARENT_WS=.*other\\ (1)$' makefile || { cat makefile >&2; fail "E: add-parent wrote the wrong form"; }
printf 'PREREQS=Lib\n.include <mk.framework.mk>\n' > App/makefile
printf 'PARENT_WS=\n.include <mk.workspace.mk>\n' > makefile
bmake >build.log 2>&1 || { tail -20 build.log >&2; fail "E: the workspace did not build"; }
# (mingw-w64 and MSVC programs end a line with CRLF)
[ "$(bmake run PROGRAM=app 2>&1 | tail -1 | tr -d '\r')" = 42 ] || fail "E: bmake run did not run the program"
# a compiled ATF test through kyua
if command -v kyua >/dev/null 2>&1 && { atf_bundled || atf_pc --exists atf-c 2>/dev/null; }; then
    printf 'TEST_PROG=math_test\nLIBS=math\n.include <mk.tst.mk>\n' > Lib/math.tst/makefile
    printf '#include <atf-c.h>\n#include "math.h"\nATF_TC_WITHOUT_HEAD(t);\nATF_TC_BODY(t, tc) { ATF_REQUIRE_EQ(dbl(4), 8); }\nATF_TP_ADD_TCS(tp) { ATF_TP_ADD_TC(tp, t); return atf_no_error(); }\n' > Lib/math.tst/src/math_test.c
    bmake test >test.log 2>&1 || { tail -20 test.log >&2; fail "E: bmake test failed"; }
    grep -q "math_test:t  *->  *passed" test.log || fail "E: the test did not run"
else
    echo "E: test skipped (no kyua or ATF)" >&2
fi
# docs
if command -v doxygen >/dev/null 2>&1; then
    bmake docs >docs.log 2>&1 || { tail -20 docs.log >&2; fail "E: bmake docs failed"; }
    [ -f build/docs/index.html ] && [ -f Lib/docs/html/index.html ] || fail "E: docs were not generated"
else
    echo "E: docs skipped (no doxygen)" >&2
fi

# --- F ----------------------------------------------------------------------
# the HTML dashboards: a name is written as HTML text and as a link
F="$SP/F/R&D"
mkdir -p "$F/A&B/m&m.m/src"
printf 'PARENT_WS=\n.include <mk.workspace.mk>\n' > "$F/makefile"
printf 'PREREQS=\n.include <mk.framework.mk>\n' > "$F/A&B/makefile"
printf 'PROG=x\n.include <mk.prog.mk>\n' > "$F/A&B/m&m.m/makefile"
echo 'int main(void) { return 0; }' > "$F/A&B/m&m.m/src/main.c"
( cd "$F" && bmake REPORT=yes >report.log 2>&1 ) || { tail -20 "$F/report.log" >&2; fail "F: bmake REPORT=yes failed"; }
html=$(find "$F/build-report" -name index.html -path '*/latest/*' | head -1)
[ -n "$html" ] || fail "F: no build dashboard"
grep -q 'R&amp;D build dashboard' "$html" || { cat "$html" >&2; fail "F: the workspace name is not escaped in the dashboard"; }
grep -q '<td>A&amp;B</td><td>m&amp;m.m</td>' "$html" || { cat "$html" >&2; fail "F: the framework and module names are not escaped in the dashboard"; }
grep -q 'href="[^"]*A%26B/m%26m.m/' "$html" || { cat "$html" >&2; fail "F: the log link is not a valid URL"; }

echo "special-path-features OK"
