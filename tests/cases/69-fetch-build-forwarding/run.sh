#!/bin/sh
# fetch-build-forwarding-fix-req: three real bugs found building lasviewer
# against GDAL/PDAL-class FETCH_BUILD=cmake dependencies, all exercised
# together here since they only show up when one fetch-built module
# depends on another:
#  - a sibling FETCH_BUILD= module's install prefix is forwarded via
#    CMAKE_PREFIX_PATH, so find_package() can locate it (module B here
#    depends on module A the same way copc-lib depended on laz-perf);
#  - LIB= names containing '-' (matching real upstream project names)
#    produce a valid, sanitized <LIB>_BUILDING macro, not a broken
#    compiler argument;
#  - on macOS, no mismatched-deployment-target linker warning between a
#    fetch-built dependency and the rest of the build.
set -eu
ROOT=$(pwd)

sha256() {
    (sha256sum "$1" 2>/dev/null || shasum -a 256 "$1" 2>/dev/null) | awk '{print $1}'
}
if ! command -v cmake >/dev/null 2>&1; then
    echo "skip: cmake not found on PATH" >&2
    exit 77
fi

# --- module A: a real CMake project, exports a CMake package config so
# find_package(aaa CONFIG) works the way a real laz-perf install does.
mkdir -p "$ROOT/fake/upstream-a"
cat > "$ROOT/fake/upstream-a/CMakeLists.txt" <<'EOF'
cmake_minimum_required(VERSION 3.10)
project(aaa C)
add_library(aaa STATIC aaa.c)
install(TARGETS aaa EXPORT aaaTargets DESTINATION lib)
install(FILES aaa.h DESTINATION include)
install(EXPORT aaaTargets FILE aaaConfig.cmake DESTINATION lib/cmake/aaa)
EOF
cat > "$ROOT/fake/upstream-a/aaa.h" <<'EOF'
#ifndef AAA_H
#define AAA_H
int aaa_value(void);
#endif
EOF
cat > "$ROOT/fake/upstream-a/aaa.c" <<'EOF'
#include "aaa.h"
int aaa_value(void) { return 42; }
EOF
( cd "$ROOT/fake" && tar czf upstream-a.tar.gz upstream-a )
HASH_A=$(sha256 "$ROOT/fake/upstream-a.tar.gz")
cat > "$ROOT/ws/Fw/liba.m/distinfo" <<EOF
SHA256 (upstream-a.tar.gz) = $HASH_A
EOF
cat > "$ROOT/ws/Fw/liba.m/makefile" <<EOF
LIB=aaa
IMPORT=fetch:aaa
FETCH_URL=file://$ROOT/fake/upstream-a.tar.gz
FETCH_BUILD=cmake
IMPORT_HEADERS=aaa.h
.include <mk.lib.mk>
EOF

# --- module B: LIB= contains '-' (a dashed upstream name), depends on A
# via find_package(), built SHARED so cmake's own link embeds aaa's
# symbols directly (no Bmake It-level transitivity needed for this test).
mkdir -p "$ROOT/fake/upstream-b"
# The CMake target name matches LIB=b-dashed exactly (as a real fetched
# project's own upstream name would) -- _stage_import: searches for
# lib${LIB}.{a,so,dylib}, so the produced filename has to match what
# Bmake It was told to expect, same as any fetch-bin:/FETCH_BUILD=
# import already requires.
cat > "$ROOT/fake/upstream-b/CMakeLists.txt" <<'EOF'
cmake_minimum_required(VERSION 3.10)
project(b-dashed C)
find_package(aaa CONFIG REQUIRED)
add_library(b-dashed SHARED bbb.c)
target_link_libraries(b-dashed PRIVATE aaa)
install(TARGETS b-dashed DESTINATION lib)
install(FILES bbb.h DESTINATION include)
EOF
cat > "$ROOT/fake/upstream-b/bbb.h" <<'EOF'
#ifndef BBB_H
#define BBB_H
int bbb_value(void);
#endif
EOF
cat > "$ROOT/fake/upstream-b/bbb.c" <<'EOF'
#include "bbb.h"
extern int aaa_value(void);
int bbb_value(void) { return aaa_value() + 1; }
EOF
( cd "$ROOT/fake" && tar czf upstream-b.tar.gz upstream-b )
HASH_B=$(sha256 "$ROOT/fake/upstream-b.tar.gz")
cat > "$ROOT/ws/Fw/libb-dashed.m/distinfo" <<EOF
SHA256 (upstream-b.tar.gz) = $HASH_B
EOF
cat > "$ROOT/ws/Fw/libb-dashed.m/makefile" <<EOF
LIB=b-dashed
IMPORT=fetch:b-dashed
FETCH_URL=file://$ROOT/fake/upstream-b.tar.gz
FETCH_BUILD=cmake
IMPORT_HEADERS=bbb.h
.include <mk.lib.mk>
EOF

cd ws
bmake >build1.log 2>&1
bin=$(find . -type f -name app | head -1)
[ -n "$bin" ]
out=$("$bin")
echo "$out" | grep -q "^43$"

# find_package(aaa) succeeded -- proof the cross-fetch-dependency prefix
# was actually forwarded, not that the build happened to work some
# other way.
grep -qi "found aaa\|Found aaa\|aaaConfig" build1.log || ! grep -qi "could not find\|not found.*aaa" build1.log

# No mismatched-deployment-target linker warning (macOS only -- harmless
# elsewhere since the pattern just won't match).
if grep -q "was built for newer 'macOS' version\|but linking with dylib.*built for newer version" build1.log; then
    echo "expected no deployment-target mismatch warning" >&2
    exit 1
fi

echo "fetch-build-forwarding OK"
