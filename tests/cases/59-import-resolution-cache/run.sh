#!/bin/sh
# import-resolution-cache-req: a second build with nothing changed must
# not re-invoke pkg-config at all -- proven with a real call-counting
# stub, not just by inspecting the cache file's own existence. Only the
# actual RESOLUTION is cached; STAGING (item 4's own inputs-hash
# mechanism) already skipped redundant work before this, verified
# separately in case 47/48.
set -eu
ROOT=$(pwd)
FAKE="$ROOT/fake"
CC=${CC:-cc}

"$CC" -c -I"$FAKE/pkgroot/include" "$FAKE/src/impl.c" -o "$FAKE/src/impl.o"
ar rcs "$FAKE/pkgroot/lib/libcached.a" "$FAKE/src/impl.o"
cat > "$FAKE/pkgroot/lib/pkgconfig/cached.pc" <<EOF
prefix=$FAKE/pkgroot
includedir=\${prefix}/include
libdir=\${prefix}/lib

Name: cached
Description: fake test lib for the resolution-cache test (self-contained)
Version: 1.0
Cflags: -I\${includedir}
Libs: -L\${libdir} -lcached
EOF

export PKG_CONFIG_PATH="$FAKE/pkgroot/lib/pkgconfig"
export REAL_PKG_CONFIG=$(command -v pkg-config)
export COUNTER_FILE="$ROOT/pkgconfig-calls.log"
: > "$COUNTER_FILE"
export PATH="$FAKE/bin:$PATH"

cd ws

bmake >build1.log 2>&1
count1=$(wc -l < "$COUNTER_FILE")
[ "$count1" -gt 0 ] || { echo "expected at least one real pkg-config call on the first build" >&2; exit 1; }

bin=$(find . -type f -name app | head -1)
[ -n "$bin" ]
out=$("$bin")
echo "$out" | grep -q "cached-value"

# Second build, nothing changed at all -- must not call pkg-config again.
bmake >build2.log 2>&1
count2=$(wc -l < "$COUNTER_FILE")
if [ "$count2" -ne "$count1" ]; then
    echo "expected no new pkg-config calls on an unchanged second build (was $count1, now $count2)" >&2
    exit 1
fi

# A genuinely changed input (PKG_CONFIG_PATH itself) must invalidate the
# cache and re-resolve for real.
export PKG_CONFIG_PATH="$FAKE/pkgroot/lib/pkgconfig:/tmp/irrelevant-but-different"
bmake >build3.log 2>&1
count3=$(wc -l < "$COUNTER_FILE")
[ "$count3" -gt "$count2" ] || { echo "expected a changed PKG_CONFIG_PATH to trigger real re-resolution" >&2; exit 1; }

echo "import-resolution-cache OK"
