#!/bin/sh
# import-headers-glob-req: an IMPORT_HEADERS= entry containing a shell
# glob metacharacter stages every match, not just one exact name --
# found in real use (GDAL installs ~150 loose headers directly in its
# includedir, no per-package subdirectory to stage wholesale the way
# IMPORT_HEADERS= already could; a real project had to hand-list the 49
# it actually used). Proven here with a fake prefix mixing matching and
# non-matching headers: only the matches are staged, and the build
# actually links and runs against the real compiled library, not just
# a header check.
set -eu
ROOT=$(pwd)
FAKE="$ROOT/fake/fakepkg"

mkdir -p "$FAKE/include" "$FAKE/lib/pkgconfig"
cat > "$FAKE/include/gdal_a.h" <<'EOF'
#define GDAL_A 7
EOF
cat > "$FAKE/include/gdal_b.h" <<'EOF'
#define GDAL_B 1
EOF
cat > "$FAKE/include/unrelated.h" <<'EOF'
#define UNRELATED_SHOULD_NOT_BE_STAGED 1
EOF

cat > "$ROOT/fake/many.c" <<'EOF'
int many_value(void) { return 42; }
EOF
CC=${CC:-cc}
"$CC" -I"$FAKE/include" -dynamiclib -o "$FAKE/lib/libmany.dylib" "$ROOT/fake/many.c" 2>/dev/null \
    || "$CC" -I"$FAKE/include" -shared -o "$FAKE/lib/libmany.so" "$ROOT/fake/many.c"

cat > "$FAKE/lib/pkgconfig/many.pc" <<EOF
prefix=$FAKE
includedir=\${prefix}/include
libdir=\${prefix}/lib

Name: many
Description: fake test lib with many loose headers (self-contained)
Version: 1.0
Cflags: -I\${includedir}
Libs: -L\${libdir} -lmany
EOF

export PKG_CONFIG_PATH="$FAKE/lib/pkgconfig"

cd ws
bmake >build1.log 2>&1
bin=$(find . -type f -name app | head -1)
[ -n "$bin" ]
out=$("$bin")
echo "$out" | grep -q "^7 42$"

incdir=$(find . -type d -path "*Fw/build/*/include" | head -1)
[ -n "$incdir" ]
[ -f "$incdir/gdal_a.h" ]
[ -f "$incdir/gdal_b.h" ]
[ ! -e "$incdir/unrelated.h" ]

echo "import-headers-glob OK"
