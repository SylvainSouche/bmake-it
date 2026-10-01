#!/bin/sh
# noop-rebuild-fix-req: a second, completely unchanged build of an
# IMPORT=fetch: (source kind) module must be a genuine no-op -- no
# recompile, no re-archive. Found in real use (lasviewer): a .PHONY
# _fetch_import target listed directly as a prerequisite of each .o:
# rule forced bmake to treat every object as stale on every single
# build, regardless of whether anything had actually changed (a .PHONY
# prerequisite has no mtime of its own, so make always treats its
# dependents as out of date) -- "libimgui.a ... re-archived" every
# time, "touching one Geo source costs about 45s". Proven here by
# counting actual compiler/archiver invocations across three
# consecutive, untouched rebuilds: must be zero after the first.
set -eu
ROOT=$(pwd)

sha256() {
    (sha256sum "$1" 2>/dev/null || shasum -a 256 "$1" 2>/dev/null) | awk '{print $1}'
}

mkdir -p "$ROOT/fake/upstream/foo-1.0"
cat > "$ROOT/fake/upstream/foo-1.0/foo.c" <<'EOF'
const char *foo_msg(void) { return "v1"; }
EOF
mkdir -p "$ROOT/fake/dist"
( cd "$ROOT/fake/upstream" && tar czf "$ROOT/fake/dist/foo-1.0.tar.gz" foo-1.0 )
HASH=$(sha256 "$ROOT/fake/dist/foo-1.0.tar.gz")
cat > "$ROOT/ws/Fw/libfoo.m/distinfo" <<EOF
SHA256 (foo-1.0.tar.gz) = $HASH
EOF
cat > "$ROOT/ws/Fw/libfoo.m/makefile" <<EOF
LIB=foo
IMPORT=fetch:foo
FETCH_URL=file://$ROOT/fake/dist/foo-1.0.tar.gz
SRCS=foo.c
.include <mk.lib.mk>
EOF

cd ws/Fw/libfoo.m
bmake >build1.log 2>&1
grep -q "===> fetched+extracted" build1.log

for i in 2 3 4; do
    bmake >build$i.log 2>&1
    n=$(grep -c "clang\|cc \|gcc " build$i.log || true)
    if [ "$n" -ne 0 ]; then
        echo "expected build $i to be a genuine no-op (0 compile/archive commands), got $n" >&2
        cat build$i.log >&2
        exit 1
    fi
done

# A genuine change (new FETCH_URL=, different content) still correctly
# triggers a real rebuild -- the fix must not have broken invalidation.
mkdir -p "$ROOT/fake/upstream2/foo-1.0"
cat > "$ROOT/fake/upstream2/foo-1.0/foo.c" <<'EOF'
const char *foo_msg(void) { return "v2"; }
EOF
( cd "$ROOT/fake/upstream2" && tar czf "$ROOT/fake/dist/foo-2.0.tar.gz" foo-1.0 )
HASH2=$(sha256 "$ROOT/fake/dist/foo-2.0.tar.gz")
cat >> distinfo <<EOF
SHA256 (foo-2.0.tar.gz) = $HASH2
EOF
sed -i.bak "s#FETCH_URL=.*#FETCH_URL=file://$ROOT/fake/dist/foo-2.0.tar.gz#" makefile
bmake >build_changed.log 2>&1
grep -q "===> fetched+extracted" build_changed.log
n=$(grep -c "clang\|cc \|gcc " build_changed.log || true)
[ "$n" -gt 0 ]
grep -q "v2" work/_resolved/foo.c

echo "noop-rebuild-fetch OK"
