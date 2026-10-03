#!/bin/sh
# test-builds-prerequisite-closure-req (lasviewer rounds 7-8, item 1): from a
# clean tree, `bmake test` alone must build the frameworks it can reach, not
# only those that have tests. Imp has NO tests and only stages an imported
# header; App (PREREQS=Imp) has a test that includes it. `test` used to enter
# App only, so imp/api.h was never staged and the test failed to compile
# ("'imp/api.h' file not found"). Needs atf (skips, 77, without it).
set -eu
pkg-config --exists atf-c 2>/dev/null || exit 77
command -v kyua >/dev/null 2>&1 || exit 77
ROOT=$(pwd)
FAKE="$ROOT/fake/fakepkg"
mkdir -p "$FAKE/include/imp" "$FAKE/lib/pkgconfig" "$ROOT/fake/src"
printf '#pragma once\nint imp_value(void);\n' > "$FAKE/include/imp/api.h"
echo 'int imp_value(void) { return 42; }' > "$ROOT/fake/src/impl.c"
${CC:-cc} -c "$ROOT/fake/src/impl.c" -o "$ROOT/fake/src/impl.o"
ar rcs "$FAKE/lib/libimp.a" "$ROOT/fake/src/impl.o"
cat > "$FAKE/lib/pkgconfig/imp.pc" <<PCEOF
prefix=$FAKE
includedir=\${prefix}/include
libdir=\${prefix}/lib
Name: imp
Description: fake
Version: 1.0
Cflags: -I\${includedir}
Libs: -L\${libdir} -limp
PCEOF
export PKG_CONFIG_PATH="$FAKE/lib/pkgconfig"
printf 'LIB=imp\nIMPORT=pkg:imp\nIMPORT_HEADERS=imp\n.include <mk.lib.mk>\n' > ws/Imp/libimp.m/makefile
printf 'PROG=app\nLIBS=imp\nTESTS_C=app_test\n.include <mk.prog.mk>\n' > ws/App/app.m/makefile

cd ws
# A clean tree: nothing built, nothing staged.
rc=0; bmake test >test.log 2>&1 || rc=$?
[ $rc = 0 ] || { echo "bmake test from a clean tree failed:" >&2; tail -15 test.log >&2; exit 1; }
grep -q "app_test:value  *->  *passed" test.log
# The untested framework was built and staged by it.
[ -f Imp/build/*/include/imp/api.h ] || ls Imp/build/*/include/imp/api.h >/dev/null

# Run alone at framework scope it also builds its PREREQS= closure.
bmake clean >/dev/null 2>&1
rc=0; ( cd App && bmake test >../test2.log 2>&1 ) || rc=$?
[ $rc = 0 ] || { echo "framework-scope bmake test from a clean tree failed:" >&2; tail -15 test2.log >&2; exit 1; }
grep -q "app_test:value  *->  *passed" test2.log

echo "test-builds-closure OK"
