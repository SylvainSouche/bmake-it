#!/bin/sh
# import-resolution-cache-req: a second build with nothing changed must
# not re-invoke pkg-config at all -- proven with a real call-counting
# stub, not just by inspecting the cache file's own existence. Only the
# actual RESOLUTION is cached; STAGING (item 4's own inputs-hash
# mechanism) already skipped redundant work before this, verified
# separately in case 47/48.
#
# import-resolution-cache-req-v2: only a SUCCESSFUL resolution is cached.
# The package is first missing (its .pc not yet written), then installed
# with nothing else changed -- the next build must find it, not replay a
# cached "not found" (OpenRider on Cygwin, 2026-10-15).
set -eu
. "$BMK_TESTLIB"
ROOT=$(pwd)
FAKE="$ROOT/fake"
CC=${CC:-cc}

mkdir -p "$FAKE/pkgroot/lib/pkgconfig"
"$CC" -c -I"$FAKE/pkgroot/include" "$FAKE/src/impl.c" -o "$FAKE/src/impl.o"
fake_ar "$FAKE/pkgroot/lib/libcached.a" "$FAKE/src/impl.o"

export PKG_CONFIG_PATH="$FAKE/pkgroot/lib/pkgconfig"
export REAL_PKG_CONFIG=$(command -v pkg-config)
export COUNTER_FILE="$ROOT/pkgconfig-calls.log"
: > "$COUNTER_FILE"
export PATH="$FAKE/bin:$PATH"
# Under ABI=mingw Bmake It asks the mingw pkg-config (pkg-config-matches-
# output-abi-req): count calls under that name too, delegating to the real one.
if [ "${ABI:-}" = mingw ]; then
    real_m=$(command -v x86_64-w64-mingw32-pkg-config)
    printf '#!/bin/sh\nREAL_PKG_CONFIG=%s exec %s "$@"\n' "$real_m" "$FAKE/bin/pkg-config" > "$FAKE/bin/x86_64-w64-mingw32-pkg-config"
    chmod +x "$FAKE/bin/x86_64-w64-mingw32-pkg-config"
fi

# Not installed yet: the build fails, and leaves no cache behind.
rc=0; (cd ws && bmake >build0.log 2>&1) || rc=$?
[ "$rc" != 0 ] || { echo "expected the build to fail while the package is not installed" >&2; exit 1; }
if [ -n "$(find ws -name '.import-resolve-cache*')" ]; then
    echo "a failed resolution must not be cached" >&2; exit 1
fi
count0=$(wc -l < "$COUNTER_FILE")

# "Install" it -- PKG_CONFIG_PATH and everything else in the cache key unchanged.
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

cd ws

bmake >build1.log 2>&1 || { echo "the package was installed after a failed build, but the next build still did not find it:" >&2; tail -5 build1.log >&2; exit 1; }
count1=$(wc -l < "$COUNTER_FILE")
[ "$count1" -gt "$count0" ] || { echo "expected real pkg-config calls once the package is installed" >&2; exit 1; }

bin=$(find . -type f -name "$(prog_name app)" | head -1)
[ -n "$bin" ]
out=$(run_prog "$bin")
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
