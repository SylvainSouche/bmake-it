#!/bin/sh
# fetch-import-source-req/fetch-distinfo-checksum-req/fetch-cache-never-
# committed-req: IMPORT=fetch:<label> fetches a distfile over FETCH_URL=,
# verifies it against a committed distinfo (SHA-256), extracts it,
# applies FETCH_PATCHES= (proving the patch actually changes behavior,
# not just that `patch` exited 0), and compiles the result through the
# ordinary SRCS= pipeline -- no upstream build-system delegation. A
# cache hit skips the real fetch even when FETCH_URL= is pointed at an
# unreachable location, as long as the already-downloaded distfile
# (matched by basename) still verifies. Multiple FETCH_URL= mirrors fail
# over to the next entry when an earlier one is unreachable.
set -eu
ROOT=$(pwd)

sha256() {
    (sha256sum "$1" 2>/dev/null || shasum -a 256 "$1" 2>/dev/null) | awk '{print $1}'
}

# --- build the fake "upstream" distfile -----------------------------------
mkdir -p "$ROOT/fake/upstream/fakelib-1.0"
cat > "$ROOT/fake/upstream/fakelib-1.0/greet.h" <<'EOF'
#ifndef FAKELIB_GREET_H
#define FAKELIB_GREET_H
const char *fakelib_greet(void);
#endif
EOF
cat > "$ROOT/fake/upstream/fakelib-1.0/greet.c" <<'EOF'
#include "greet.h"

const char *fakelib_greet(void) {
    return "hello from original fakelib";
}
EOF

mkdir -p "$ROOT/fake/dist"
( cd "$ROOT/fake/upstream" && tar czf "$ROOT/fake/dist/fakelib-1.0.tar.gz" fakelib-1.0 )
HASH=$(sha256 "$ROOT/fake/dist/fakelib-1.0.tar.gz")

# --- build a patch that changes fetched-source behavior -------------------
mkdir -p "$ROOT/fake/patched/fakelib-1.0"
cat > "$ROOT/fake/patched/fakelib-1.0/greet.c" <<'EOF'
#include "greet.h"

const char *fakelib_greet(void) {
    return "hello from original fakelib, patched";
}
EOF
PATCH_DIR="$ROOT/ws/Fw/libfakelib.m/patches"
mkdir -p "$PATCH_DIR"
diff -u -L a/greet.c -L b/greet.c \
    "$ROOT/fake/upstream/fakelib-1.0/greet.c" \
    "$ROOT/fake/patched/fakelib-1.0/greet.c" \
    > "$PATCH_DIR/fix-greeting.patch" || true
[ -s "$PATCH_DIR/fix-greeting.patch" ]

# --- distinfo (committed alongside the module, generated here since the
# distfile is itself a test fixture built above) --------------------------
cat > "$ROOT/ws/Fw/libfakelib.m/distinfo" <<EOF
SHA256 (fakelib-1.0.tar.gz) = $HASH
EOF

# --- the module makefile (FETCH_URL= embeds a runtime tmp path, so it's
# generated here rather than committed statically, same reason case
# 47-import-libraries-pkgconfig generates its .pc file at test time) -----
cat > "$ROOT/ws/Fw/libfakelib.m/makefile" <<EOF
LIB=fakelib
IMPORT=fetch:fakelib
FETCH_URL=file://$ROOT/fake/dist/fakelib-1.0.tar.gz
FETCH_PATCHES=fix-greeting.patch
SRCS=greet.c
IMPORT_HEADERS=greet.h
.include <mk.lib.mk>
EOF

cd ws
bmake >build1.log 2>&1
bin=$(find . -type f -name app | head -1)
[ -n "$bin" ]
out=$("$bin")
echo "$out" | grep -q "hello from original fakelib, patched"
grep -q "verified fakelib-1.0.tar.gz (sha256 ok)" build1.log
grep -q "fetched+extracted fakelib-1.0.tar.gz" build1.log

# --- cache hit: FETCH_URL= now points at an unreachable directory, but
# shares the same basename as the already-downloaded, already-verified
# distfile -- the fetch loop must reuse it from distfiles/ without ever
# attempting the network/file access again.
cd Fw/libfakelib.m
DEAD_URL="file:///no/such/directory/fakelib-1.0.tar.gz"
bmake FETCH_URL="$DEAD_URL" all >build2.log 2>&1
grep -q "verified fakelib-1.0.tar.gz (sha256 ok)" build2.log

# --- multiple mirrors: force a genuinely fresh extraction (clear the
# local distfile + work tree), then give FETCH_URL= two entries with the
# same basename -- the first unreachable, the second the real path.
# Fallover to the second must still succeed.
rm -rf work distfiles
bmake FETCH_URL="file:///no/such/directory/fakelib-1.0.tar.gz file://$ROOT/fake/dist/fakelib-1.0.tar.gz" all >build3.log 2>&1
grep -q "fetched+extracted fakelib-1.0.tar.gz" build3.log

echo "fetch-import-source OK"
