#!/bin/sh
# repeated-messages-fix-req (lasviewer round 5, item 4): progress messages
# appear only when the work they describe happened. A fetch: + SRCS=
# module's header staging ("staged header ...") and the "built shared"
# message used to repeat on every visit even though nothing was copied or
# linked (all: printed it, and _stage_fetch_headers: had no guard).
# Built from the workspace root, as a real project is: the framework
# creates its build/<key>/ directories before any module is parsed (a
# standalone module build would see one appear between its first and
# second run and legitimately rebuild once).
set -eu
ROOT=$(pwd)

sha256() {
    (sha256sum "$1" 2>/dev/null || shasum -a 256 "$1" 2>/dev/null) | awk '{print $1}'
}

mkdir -p "$ROOT/fake/upstream/foo-1.0" "$ROOT/fake/dist"
cat > "$ROOT/fake/upstream/foo-1.0/foo.c" <<'XEOF'
const char *foo_msg(void) { return "v1"; }
XEOF
echo '#define FOO_H 1' > "$ROOT/fake/upstream/foo-1.0/foo.h"
( cd "$ROOT/fake/upstream" && tar czf "$ROOT/fake/dist/foo-1.0.tar.gz" foo-1.0 )
HASH=$(sha256 "$ROOT/fake/dist/foo-1.0.tar.gz")
cd ws
M=Fw/libfoo.m
echo "SHA256 (foo-1.0.tar.gz) = $HASH" > $M/distinfo
cat > $M/makefile <<MEOF
LIB=foo
IMPORT=fetch:foo
FETCH_URL=file://$ROOT/fake/dist/foo-1.0.tar.gz
IMPORT_HEADERS=foo.h
SRCS=foo.c
.include <mk.lib.mk>
MEOF

bmake >build1.log 2>&1
[ "$(grep -c 'staged header foo.h' build1.log)" = 1 ]
[ "$(grep -c '===> built shared' build1.log)" = 1 ]

for i in 2 3; do
    bmake >build$i.log 2>&1
    if grep -qE 'staged header|===> built (shared|static)' build$i.log; then
        echo "build $i repeated a message although nothing changed:" >&2
        grep -E 'staged header|===> built' build$i.log >&2
        exit 1
    fi
done

# A real change re-stages and re-links, and says so once. (bmake compares
# mtimes at one-second granularity: without this pause the new object can
# look "not newer" than the library linked in the same second.)
sleep 1
mkdir -p "$ROOT/fake/upstream2/foo-1.0"
cat > "$ROOT/fake/upstream2/foo-1.0/foo.c" <<'XEOF'
const char *foo_msg(void) { return "v2"; }
XEOF
echo '#define FOO_H 2' > "$ROOT/fake/upstream2/foo-1.0/foo.h"
( cd "$ROOT/fake/upstream2" && tar czf "$ROOT/fake/dist/foo-2.0.tar.gz" foo-1.0 )
echo "SHA256 (foo-2.0.tar.gz) = $(sha256 "$ROOT/fake/dist/foo-2.0.tar.gz")" >> $M/distinfo
sed -i.bak "s#FETCH_URL=.*#FETCH_URL=file://$ROOT/fake/dist/foo-2.0.tar.gz#" $M/makefile
bmake >build_changed.log 2>&1
[ "$(grep -c 'staged header foo.h' build_changed.log)" = 1 ]
[ "$(grep -c '===> built shared' build_changed.log)" = 1 ]

echo "repeated-messages OK"
