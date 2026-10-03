#!/bin/sh
# import-system-includedir-fallback-req (lasviewer round 6, item 2):
# pkg-config omits -I<dir> for a SYSTEM include directory (/usr/include on
# Linux), so `pkg-config --cflags glm` prints nothing and header staging,
# which only read the -I flags, failed with "not found under any resolved
# include dir ()". Simulated portably: a .pc whose Cflags: is empty but
# whose includedir names the real header directory -- exactly what
# pkg-config reports for a package installed in a system directory.
set -eu
ROOT=$(pwd)
FAKE="$ROOT/fake/fakepkg"
CC=${CC:-cc}
"$CC" -c "$ROOT/fake/fakesrc/impl.c" -o "$ROOT/fake/fakesrc/impl.o"
ar rcs "$FAKE/lib/libsys1.a" "$ROOT/fake/fakesrc/impl.o"
cat > "$FAKE/lib/pkgconfig/sys1.pc" <<PCEOF
prefix=$FAKE
includedir=\${prefix}/include
libdir=\${prefix}/lib

Name: sys1
Description: fake package in a "system" include dir (no -I in Cflags)
Version: 1.0
Cflags:
Libs: -L\${libdir} -lsys1
PCEOF
export PKG_CONFIG_PATH="$FAKE/lib/pkgconfig"

# The premise: --cflags really is empty, --variable=includedir is not.
[ -z "$(pkg-config --cflags sys1)" ]
[ "$(pkg-config --variable=includedir sys1)" = "$FAKE/include" ]

cd ws
bmake >build1.log 2>&1
bin=$(find . -type f -name app | head -1)
[ -n "$bin" ]
"$bin" | grep -q "hello from a system-include import"
grep -q "staged header(s) sys1 from $FAKE/include" build1.log

# A genuinely absent header still fails, naming where it looked.
printf 'LIB=sys1\nIMPORT=pkg:sys1\nIMPORT_HEADERS=absent-3f8a2b\n.include <mk.lib.mk>\n' > Fw/libsys1.m/makefile
( cd Fw/libsys1.m && bmake clean >/dev/null 2>&1 )
if bmake >build2.log 2>&1; then echo "expected an absent header to fail" >&2; exit 1; fi
grep -q "IMPORT_HEADERS=absent-3f8a2b: not found under any resolved include dir" build2.log
grep -q "$FAKE/include" build2.log
echo "import-system-includedir OK"
