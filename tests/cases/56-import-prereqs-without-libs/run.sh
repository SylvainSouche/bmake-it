#!/bin/sh
# imported-libraries-are-ordinary-modules-req / 20-headers-and-linking.md:
# PREREQS= grants header visibility only; LIBS= is the separate, link-time
# instruction -- for an IMPORT=-resolved framework exactly as for a
# compiled one. PREREQS=Ext alone lets App #include the imported header
# (compiles) but must fail to LINK (undefined symbol) without LIBS=ext;
# adding LIBS=ext must then link and run correctly.
set -eu
ROOT=$(pwd)
FAKE="$ROOT/fake"
CC=${CC:-cc}

"$CC" -c -I"$FAKE/pkgroot/include" "$FAKE/src/impl.c" -o "$FAKE/src/impl.o"
ar rcs "$FAKE/pkgroot/lib/libext.a" "$FAKE/src/impl.o"
cat > "$FAKE/pkgroot/lib/pkgconfig/ext.pc" <<EOF
prefix=$FAKE/pkgroot
includedir=\${prefix}/include
libdir=\${prefix}/lib

Name: ext
Description: fake test lib (self-contained)
Version: 1.0
Cflags: -I\${includedir}
Libs: -L\${libdir} -lext
EOF
export PKG_CONFIG_PATH="$FAKE/pkgroot/lib/pkgconfig"

(cd ws/Ext/libext.m && bmake copy-up)

cd ws/App/app.m
if bmake all 2>err.log; then
    echo "expected link to fail without LIBS=ext (PREREQS= is headers-only)" >&2
    exit 1
fi
grep -qi "undefined" err.log

{ echo "LIBS=ext"; cat makefile; } > makefile.new && mv makefile.new makefile
bmake clean >/dev/null 2>&1
bmake all >build.log 2>&1
out=$(./build/*/bin/app)
echo "$out" | grep -q "ext-value"

echo "import-prereqs-without-libs OK"
