#!/bin/sh
# fetch-build-req: FETCH_BUILD=custom runs FETCH_BUILD_CMD= verbatim for
# a build system with no built-in preset, cwd the resolved work tree,
# with BMK_FETCH_SRCDIR/BMK_FETCH_BUILD_DIR/BMK_FETCH_INSTALL_PREFIX
# exported. Proves the escape hatch itself, that Bmake It's own CC is
# forwarded into the command's environment, and that the result is
# staged and runnable exactly like any other fetch-build import.
set -eu
ROOT=$(pwd)

sha256() {
    (sha256sum "$1" 2>/dev/null || shasum -a 256 "$1" 2>/dev/null) | awk '{print $1}'
}

mkdir -p "$ROOT/fake/upstream/foo-1.0"
cat > "$ROOT/fake/upstream/foo-1.0/foo.h" <<'EOF'
#ifndef FOO_H
#define FOO_H
const char *foo_greet(void);
#endif
EOF
cat > "$ROOT/fake/upstream/foo-1.0/foo.c" <<'EOF'
#include "foo.h"
const char *foo_greet(void) {
    return "hello from a custom FETCH_BUILD_CMD";
}
EOF

mkdir -p "$ROOT/fake/dist"
( cd "$ROOT/fake/upstream" && tar czf "$ROOT/fake/dist/foo-1.0.tar.gz" foo-1.0 )
HASH=$(sha256 "$ROOT/fake/dist/foo-1.0.tar.gz")

cat > "$ROOT/ws/Fw/libfoo.m/distinfo" <<EOF
SHA256 (foo-1.0.tar.gz) = $HASH
EOF

# The custom command itself proves BMK_FETCH_INSTALL_PREFIX and the
# forwarded CC are both real and usable: it hand-builds a shared
# library and installs it with plain mkdir/cp/cc, nothing preset-shaped.
cat > "$ROOT/ws/Fw/libfoo.m/makefile" <<EOF
LIB=foo
IMPORT=fetch:foo
FETCH_URL=file://$ROOT/fake/dist/foo-1.0.tar.gz
FETCH_BUILD=custom
FETCH_BUILD_CMD=mkdir -p \$\${BMK_FETCH_INSTALL_PREFIX}/include \$\${BMK_FETCH_INSTALL_PREFIX}/lib && \$\${CC} -dynamiclib -o \$\${BMK_FETCH_INSTALL_PREFIX}/lib/libfoo.dylib foo.c && cp foo.h \$\${BMK_FETCH_INSTALL_PREFIX}/include/
IMPORT_HEADERS=foo.h
.include <mk.lib.mk>
EOF

cd ws
bmake >build1.log 2>&1
grep -q "FETCH_BUILD=custom:" build1.log
grep -q "built via FETCH_BUILD=custom" build1.log

bin=$(find . -type f -name app | head -1)
[ -n "$bin" ]
out=$("$bin")
echo "$out" | grep -q "hello from a custom FETCH_BUILD_CMD"

# FETCH_BUILD=custom with no FETCH_BUILD_CMD= is a clean, named error.
cd Fw/libfoo.m
rm -f distfiles/foo-1.0.tar.gz
sed -i.bak '/^FETCH_BUILD_CMD=/d' makefile
if bmake FETCH_BUILD_CMD= all >err.log 2>&1; then
    echo "expected FETCH_BUILD=custom with no FETCH_BUILD_CMD= to fail" >&2
    exit 1
fi
grep -q "FETCH_BUILD=custom requires FETCH_BUILD_CMD=" err.log

echo "fetch-build-custom OK"
