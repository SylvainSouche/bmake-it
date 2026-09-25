#!/bin/sh
# imported-libraries-are-ordinary-modules-req: the "swap test" -- the
# SAME library, once compiled from source and once IMPORT=-resolved,
# with the CONSUMER (app.m) never touched across the swap. Both must
# link and run correctly.
set -eu
ROOT=$(pwd)
FAKE="$ROOT/fake"
CC=${CC:-cc}

cd ws

# --- Half 1: compiled from source ---
bmake >build1.log 2>&1
bin=$(find . -type f -name app | head -1)
[ -n "$bin" ]
out=$("$bin")
echo "$out" | grep -q "compiled-swap"

# --- Half 2: swap to IMPORT=, consumer (Fw/app.m) untouched ---
"$CC" -c -I"$FAKE/pkgroot/include" "$FAKE/src/impl.c" -o "$FAKE/src/impl.o"
ar rcs "$FAKE/pkgroot/lib/libswap.a" "$FAKE/src/impl.o"
cat > "$FAKE/pkgroot/lib/pkgconfig/swap.pc" <<EOF
prefix=$FAKE/pkgroot
includedir=\${prefix}/include
libdir=\${prefix}/lib

Name: swap
Description: fake test lib for the swap test (self-contained)
Version: 1.0
Cflags: -I\${includedir}
Libs: -L\${libdir} -lswap
EOF
export PKG_CONFIG_PATH="$FAKE/pkgroot/lib/pkgconfig"

cat > Fw/libswap.m/makefile <<'MKEOF'
LIB=swap
IMPORT=pkg:swap
IMPORT_HEADERS=swap
.include <mk.lib.mk>
MKEOF

bmake clean >/dev/null 2>&1
bmake >build2.log 2>&1
out=$("$bin")
echo "$out" | grep -q "imported-swap"

echo "import-compiled-swap OK"
