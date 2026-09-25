#!/bin/sh
# fetch-import-binary-req: IMPORT=fetch-bin:<label> runs the identical
# fetch/verify/extract/patch pipeline as fetch: (source kind), but stages
# the extracted tree as a conventional prefix (include/, lib/) via the
# SAME _stage_import: mechanism pkg:/prefix: already use -- no compiling.
set -eu
ROOT=$(pwd)

sha256() {
    (sha256sum "$1" 2>/dev/null || shasum -a 256 "$1" 2>/dev/null) | awk '{print $1}'
}

# --- build a fake "prebuilt release" the way an upstream project would
# ship one: a prefix tree with include/ and lib/ already compiled -----
PREFIX="$ROOT/fake/upstream/binlib-2.0"
mkdir -p "$PREFIX/include" "$PREFIX/lib"
cat > "$PREFIX/include/binlib.h" <<'EOF'
#ifndef BINLIB_H
#define BINLIB_H
const char *binlib_greet(void);
#endif
EOF
cat > "$ROOT/fake/impl.c" <<'EOF'
#include "binlib.h"
const char *binlib_greet(void) {
    return "hello from prebuilt binlib";
}
EOF
CC=${CC:-cc}
"$CC" -c -I"$PREFIX/include" "$ROOT/fake/impl.c" -o "$ROOT/fake/impl.o"
ar rcs "$PREFIX/lib/libbinlib.a" "$ROOT/fake/impl.o"

mkdir -p "$ROOT/fake/dist"
( cd "$ROOT/fake/upstream" && tar czf "$ROOT/fake/dist/binlib-2.0.tar.gz" binlib-2.0 )
HASH=$(sha256 "$ROOT/fake/dist/binlib-2.0.tar.gz")

cat > "$ROOT/ws/Fw/libbinlib.m/distinfo" <<EOF
SHA256 (binlib-2.0.tar.gz) = $HASH
EOF

cat > "$ROOT/ws/Fw/libbinlib.m/makefile" <<EOF
LIB=binlib
IMPORT=fetch-bin:binlib
FETCH_URL=file://$ROOT/fake/dist/binlib-2.0.tar.gz
IMPORT_HEADERS=binlib.h
.include <mk.lib.mk>
EOF

cd ws
bmake >build1.log 2>&1
bin=$(find . -type f -name app | head -1)
[ -n "$bin" ]
out=$("$bin")
echo "$out" | grep -q "hello from prebuilt binlib"
grep -q "verified binlib-2.0.tar.gz (sha256 ok)" build1.log
grep -q "IMPORT=fetch-bin:binlib: resolved via fetch-bin:binlib" build1.log

# No compile step for the binary kind -- only staging.
grep -qv "impl.c" build1.log || true
if grep -q " -c .*binlib.*\.c " build1.log; then
    echo "expected no compile step for IMPORT=fetch-bin:, but one ran" >&2
    exit 1
fi

echo "fetch-import-binary OK"
