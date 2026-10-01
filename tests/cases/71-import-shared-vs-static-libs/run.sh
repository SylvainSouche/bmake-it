#!/bin/sh
# shared-import-link-flags-fix-req: a SHARED IMPORT=pkg: resolution uses
# plain `pkg-config --libs` (just this package's own -L/-l), not
# `--libs --static` (the full transitive closure) -- a shared library
# embeds its own dependency references, resolved by the dynamic linker
# at load time, not link time. `--libs --static`'s Libs.private: entries
# can validly omit their own -L (relying on the HOST's default linker
# search path), which this project's build doesn't necessarily share,
# producing `ld: library 'X' not found` for an unrelated transitive
# dependency -- found in real use importing gdal (its own lz4
# dependency). Proven here with a fake shared "big" library whose own
# .pc Libs.private: names a library that doesn't exist anywhere: the
# old code would fail to link; the fix links and runs clean.
set -eu
ROOT=$(pwd)
FAKE="$ROOT/fake/prefix"

mkdir -p "$FAKE/include" "$FAKE/lib/pkgconfig"
cat > "$FAKE/include/big.h" <<'EOF'
#ifndef BIG_H
#define BIG_H
const char *big_msg(void);
#endif
EOF
cat > "$ROOT/fake/big.c" <<'EOF'
#include "big.h"
const char *big_msg(void) { return "big"; }
EOF
CC=${CC:-cc}
"$CC" -I"$FAKE/include" -dynamiclib -o "$FAKE/lib/libbig.dylib" "$ROOT/fake/big.c" 2>/dev/null \
    || "$CC" -I"$FAKE/include" -shared -o "$FAKE/lib/libbig.so" "$ROOT/fake/big.c"

cat > "$FAKE/lib/pkgconfig/big.pc" <<EOF
prefix=$FAKE
includedir=\${prefix}/include
libdir=\${prefix}/lib

Name: big
Description: fake test lib (self-contained, no system package used)
Version: 1.0
Cflags: -I\${includedir}
Libs: -L\${libdir} -lbig
Libs.private: -lnonexistent-transitive-dep-3f8a2b
EOF

export PKG_CONFIG_PATH="$FAKE/lib/pkgconfig"

cd ws
bmake >build1.log 2>&1
bin=$(find . -type f -name app | head -1)
[ -n "$bin" ]
out=$("$bin")
echo "$out" | grep -q "big"

# The final link line must never have named the nonexistent transitive
# dependency at all.
if grep -q "nonexistent-transitive-dep" build1.log; then
    echo "expected the shared import to use plain --libs, not --static's full closure" >&2
    exit 1
fi

echo "import-shared-vs-static-libs OK"
