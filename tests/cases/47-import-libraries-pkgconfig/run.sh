#!/bin/sh
# imported-libraries-are-ordinary-modules-req / import-resolution-ladder-req
# / import-staging-req: IMPORT=pkg:<name> resolves via a real pkg-config
# .pc file, stages exactly IMPORT_HEADERS= (not a sibling header in the
# same prefix) and lib<LIB>.*, and the consumer needs nothing but ordinary
# PREREQS=/LIBS= -- no IMPORT-specific consumer-side mechanism at all.
# A missing/unresolvable IMPORT= fails loudly and names what was tried.
set -eu
ROOT=$(pwd)
FAKE="$ROOT/fake/fakepkg"

CC=${CC:-cc}
"$CC" -c "$ROOT/fake/fakesrc/impl.c" -o "$ROOT/fake/fakesrc/impl.o"
ar rcs "$FAKE/lib/libgreet2.a" "$ROOT/fake/fakesrc/impl.o"

cat > "$FAKE/lib/pkgconfig/greet2.pc" <<EOF
prefix=$FAKE
includedir=\${prefix}/include
libdir=\${prefix}/lib

Name: greet2
Description: fake test lib (self-contained, no system package used)
Version: 3.1.4
Cflags: -I\${includedir}
Libs: -L\${libdir} -lgreet2
EOF

export PKG_CONFIG_PATH="$FAKE/lib/pkgconfig"

cd ws
bmake >build1.log 2>&1
bin=$(find . -type f -name app | head -1)
[ -n "$bin" ]
out=$("$bin")
echo "$out" | grep -q "hello from fake pkg-config import"
grep -q "resolved via pkg-config:greet2" build1.log
grep -q "3.1.4" build1.log

# Only IMPORT_HEADERS=greet2 is staged -- the sibling header in the same
# prefix (include/sibling/other.h) must not be reachable.
incdir=$(find . -type d -path "*Fw/build/*/include" | head -1)
[ -n "$incdir" ]
[ -d "$incdir/greet2" ]
[ ! -e "$incdir/sibling" ]

# A missing/unresolvable import fails loudly, naming what was tried.
cd Fw/libgreet2.m
bmake clean >/dev/null 2>&1
unset PKG_CONFIG_PATH
if bmake all 2>err.log; then
    echo "expected IMPORT= resolution to fail with no pkg-config match" >&2
    exit 1
fi
grep -q "cannot resolve module libgreet2.m" err.log
grep -q "GREET2_PREFIX" err.log

echo "import-libraries-pkgconfig OK"
