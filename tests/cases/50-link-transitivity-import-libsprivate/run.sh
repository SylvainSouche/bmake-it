#!/bin/sh
# import-link-transitivity-req, IMPORT= side: pkg-config's Libs.private
# (a private, transitive-only dependency real projects lean on -- e.g.
# GDAL privately linking PROJ) must follow the imported library into a
# consumer automatically. app.m deliberately declares only LIBS=pubpkg,
# never -lpriv, proving it.
set -eu
ROOT=$(pwd)
FAKE="$ROOT/fake"
CC=${CC:-cc}

"$CC" -c -I"$FAKE/priv/include" "$FAKE/src/priv_impl.c" -o "$FAKE/src/priv_impl.o"
ar rcs "$FAKE/priv/libpriv.a" "$FAKE/src/priv_impl.o"

"$CC" -c -I"$FAKE/pub/include" -I"$FAKE/priv/include" "$FAKE/src/pub_impl.c" -o "$FAKE/src/pub_impl.o"
ar rcs "$FAKE/pub/lib/libpubpkg.a" "$FAKE/src/pub_impl.o"

cat > "$FAKE/pub/lib/pkgconfig/pubpkg.pc" <<EOF
prefix=$FAKE/pub
includedir=\${prefix}/include
libdir=\${prefix}/lib

Name: pubpkg
Description: fake pkg with a private transitive dep (self-contained)
Version: 1.0
Cflags: -I\${includedir}
Libs: -L\${libdir} -lpubpkg
Libs.private: -L$FAKE/priv -lpriv
EOF

export PKG_CONFIG_PATH="$FAKE/pub/lib/pkgconfig"

cd ws
bmake >build.log 2>&1
bin=$(find . -type f -name app | head -1)
[ -n "$bin" ]
out=$("$bin")
echo "$out" | grep -q "priv-value"

linkdeps=$(find . -name libpubpkg.linkdeps | head -1)
[ -n "$linkdeps" ]
grep -q -- "-lpriv" "$linkdeps"
grep -q -- "-lpubpkg" build.log
grep -q -- "-lpriv" build.log

echo "link-transitivity-import-libsprivate OK"
