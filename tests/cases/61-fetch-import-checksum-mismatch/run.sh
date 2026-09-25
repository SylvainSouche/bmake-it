#!/bin/sh
# fetch-distinfo-checksum-req: a distfile whose content doesn't match the
# committed distinfo's SHA-256 fails cleanly -- extraction never proceeds
# on unverified content, and the error names the module, the distfile,
# and both hashes.
set -eu
ROOT=$(pwd)

sha256() {
    (sha256sum "$1" 2>/dev/null || shasum -a 256 "$1" 2>/dev/null) | awk '{print $1}'
}

mkdir -p "$ROOT/fake/upstream/badlib-1.0" "$ROOT/fake/dist"
cat > "$ROOT/fake/upstream/badlib-1.0/thing.c" <<'EOF'
int thing(void) { return 42; }
EOF
( cd "$ROOT/fake/upstream" && tar czf "$ROOT/fake/dist/badlib-1.0.tar.gz" badlib-1.0 )

# distinfo deliberately records the WRONG hash (as if the upstream file
# was corrupted or tampered with after distinfo was committed).
cat > "$ROOT/ws/Fw/libbad.m/distinfo" <<'EOF'
SHA256 (badlib-1.0.tar.gz) = 0000000000000000000000000000000000000000000000000000000000000000
EOF

cat > "$ROOT/ws/Fw/libbad.m/makefile" <<EOF
LIB=bad
IMPORT=fetch:badlib
FETCH_URL=file://$ROOT/fake/dist/badlib-1.0.tar.gz
SRCS=thing.c
.include <mk.lib.mk>
EOF

cd ws/Fw/libbad.m
if bmake all >build.log 2>err.log; then
    echo "expected checksum mismatch to fail the build" >&2
    cat build.log err.log >&2
    exit 1
fi
grep -q "checksum mismatch for badlib-1.0.tar.gz" build.log err.log
grep -q "IMPORT=fetch:badlib" build.log err.log

# The corrupted distfile must not be left behind masquerading as valid.
[ ! -f distfiles/badlib-1.0.tar.gz ]

# A real, correctly-hashed distinfo lets the same module build cleanly
# afterward -- proving the earlier failure wasn't a false negative from
# something else being broken.
HASH=$(sha256 "$ROOT/fake/dist/badlib-1.0.tar.gz")
cat > distinfo <<EOF
SHA256 (badlib-1.0.tar.gz) = $HASH
EOF
bmake all >build2.log 2>&1
grep -q "verified badlib-1.0.tar.gz (sha256 ok)" build2.log

echo "fetch-import-checksum-mismatch OK"
