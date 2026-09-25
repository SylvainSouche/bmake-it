#!/bin/sh
# import-resolution-ladder-req: _PKG_CONFIG_EXTRA_DIRS (mk.paths.<os>.mk's
# own extension point, settable via a mk/ hook the same as any other
# bmake variable) is searched for .pc files pkg-config's own built-in
# defaults and PKG_CONFIG_PATH would never reach on their own.
set -eu
ROOT=$(pwd)
FAKE="$ROOT/fake"
CC=${CC:-cc}

"$CC" -c -I"$FAKE/pkgroot/include" "$FAKE/src/impl.c" -o "$FAKE/src/impl.o"
ar rcs "$FAKE/pkgroot/lib/libgreet4.a" "$FAKE/src/impl.o"

cat > "$FAKE/nonstandard-pcdir/greet4.pc" <<EOF
prefix=$FAKE/pkgroot
includedir=\${prefix}/include
libdir=\${prefix}/lib

Name: greet4
Description: fake test lib in a non-default pkgconfig dir (self-contained)
Version: 1.0
Cflags: -I\${includedir}
Libs: -L\${libdir} -lgreet4
EOF

cd ws/Fw/libgreet4.m

# Without _PKG_CONFIG_EXTRA_DIRS, and no PKG_CONFIG_PATH pointing at the
# non-default dir, resolution must fail cleanly.
unset PKG_CONFIG_PATH
if bmake all 2>err.log; then
    echo "expected resolution to fail without the extra pkgconfig dir" >&2
    exit 1
fi
grep -q "cannot resolve module libgreet4.m" err.log

# Add the extra dir via a mk/ hook -- resolution must now succeed.
echo "_PKG_CONFIG_EXTRA_DIRS = $FAKE/nonstandard-pcdir" > mk/pre.mk
bmake all >build.log 2>&1
grep -q "resolved via pkg-config:greet4" build.log

cd ../..
bmake >build2.log 2>&1
bin=$(find . -type f -name app | head -1)
[ -n "$bin" ]
out=$("$bin")
echo "$out" | grep -q "hello from a non-default pkgconfig dir"

echo "import-pkg-config-extra-dirs OK"
