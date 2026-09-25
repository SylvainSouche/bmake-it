#!/bin/sh
# fetch-build-req: FETCH_BUILD=cmake delegates the extracted+patched
# source to its own CMake build instead of SRCS=, installing into a
# module-local prefix and staging the result exactly like fetch-bin:.
# Proves: patches still apply before the upstream build runs; cmake
# actually invoked (not silently skipped); the consumer links and runs
# against the cmake-installed library.
set -eu
if ! command -v cmake >/dev/null 2>&1; then
    echo "skip: cmake not found on PATH" >&2
    exit 77
fi
ROOT=$(pwd)

sha256() {
    (sha256sum "$1" 2>/dev/null || shasum -a 256 "$1" 2>/dev/null) | awk '{print $1}'
}

mkdir -p "$ROOT/fake/upstream/foo-1.0"
cat > "$ROOT/fake/upstream/foo-1.0/CMakeLists.txt" <<'EOF'
cmake_minimum_required(VERSION 3.10)
project(foo C)
add_library(foo SHARED foo.c)
install(TARGETS foo DESTINATION lib)
install(FILES foo.h DESTINATION include)
EOF
cat > "$ROOT/fake/upstream/foo-1.0/foo.h" <<'EOF'
#ifndef FOO_H
#define FOO_H
const char *foo_greet(void);
#endif
EOF
cat > "$ROOT/fake/upstream/foo-1.0/foo.c" <<'EOF'
#include "foo.h"
const char *foo_greet(void) {
    return "hello from original cmake-built foo";
}
EOF

mkdir -p "$ROOT/fake/dist"
( cd "$ROOT/fake/upstream" && tar czf "$ROOT/fake/dist/foo-1.0.tar.gz" foo-1.0 )
HASH=$(sha256 "$ROOT/fake/dist/foo-1.0.tar.gz")

mkdir -p "$ROOT/fake/patched/foo-1.0"
cat > "$ROOT/fake/patched/foo-1.0/foo.c" <<'EOF'
#include "foo.h"
const char *foo_greet(void) {
    return "hello from original cmake-built foo, patched";
}
EOF
PATCH_DIR="$ROOT/ws/Fw/libfoo.m/patches"
mkdir -p "$PATCH_DIR"
diff -u -L a/foo.c -L b/foo.c \
    "$ROOT/fake/upstream/foo-1.0/foo.c" \
    "$ROOT/fake/patched/foo-1.0/foo.c" \
    > "$PATCH_DIR/fix-greeting.patch" || true
[ -s "$PATCH_DIR/fix-greeting.patch" ]

cat > "$ROOT/ws/Fw/libfoo.m/distinfo" <<EOF
SHA256 (foo-1.0.tar.gz) = $HASH
EOF

cat > "$ROOT/ws/Fw/libfoo.m/makefile" <<EOF
LIB=foo
IMPORT=fetch:foo
FETCH_URL=file://$ROOT/fake/dist/foo-1.0.tar.gz
FETCH_PATCHES=fix-greeting.patch
FETCH_BUILD=cmake
IMPORT_HEADERS=foo.h
.include <mk.lib.mk>
EOF

cd ws
bmake >build1.log 2>&1
grep -q "verified foo-1.0.tar.gz (sha256 ok)" build1.log
grep -q "FETCH_BUILD=cmake: configure && build && install" build1.log
grep -q "built via FETCH_BUILD=cmake" build1.log

bin=$(find . -type f -name app | head -1)
[ -n "$bin" ]
out=$("$bin")
echo "$out" | grep -q "hello from original cmake-built foo, patched"

# A second, fully unchanged build must NOT re-run cmake -- _fetch_build:
# is itself .PHONY (always invoked) but must short-circuit via its own
# work/.build-fp fingerprint. Still succeeds and the binary still runs,
# proving the staged library survives the cache hit too.
cd Fw/libfoo.m
bmake all >build2.log 2>&1
if grep -q "FETCH_BUILD=cmake: configure" build2.log; then
    echo "expected the cached build to skip re-running cmake" >&2
    exit 1
fi
cd "$ROOT/ws"
out2=$("$bin")
echo "$out2" | grep -q "hello from original cmake-built foo, patched"

echo "fetch-build-cmake OK"
