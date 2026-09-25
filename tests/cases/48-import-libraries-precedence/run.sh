#!/bin/sh
# import-resolution-ladder-req: first match wins, in order -- env/CLI,
# then mk/ hooks, then pkg-config, then probing. Each step is proven by
# making it the ONLY candidate first (so a wrong "it happened to still
# work" doesn't hide a bug), then adding the next, higher-precedence
# candidate and confirming the winner shifts.
set -eu
ROOT=$(pwd)
CC=${CC:-cc}

for who in probe pkg hook env; do
    "$CC" -c "$ROOT/fake/src/impl_${who}.c" -o "$ROOT/fake/src/impl_${who}.o"
    mkdir -p "$ROOT/fake/p_${who}/lib"
    ar rcs "$ROOT/fake/p_${who}/lib/libgreet3.a" "$ROOT/fake/src/impl_${who}.o"
done

mkdir -p "$ROOT/fake/p_pkg/lib/pkgconfig"
cat > "$ROOT/fake/p_pkg/lib/pkgconfig/greet3.pc" <<EOF
prefix=$ROOT/fake/p_pkg
includedir=\${prefix}/include
libdir=\${prefix}/lib

Name: greet3
Description: fake test lib (self-contained)
Version: 1.0
Cflags: -I\${includedir}
Libs: -L\${libdir} -lgreet3
EOF

MODDIR="ws/Fw/libgreet3.m"
BIN=""

build_and_check() {
    expect=$1
    ( cd ws && bmake clean >/dev/null 2>&1 || true )
    ( cd ws && bmake >build.log 2>&1 )
    [ -n "$BIN" ] || BIN=$(find ws -type f -name app | head -1)
    out=$("$BIN")
    echo "$out" | grep -q "resolved via $expect" || {
        echo "expected '$expect' to win, got: $out" >&2
        cat "ws/$MODDIR/build.log" 2>/dev/null >&2 || true
        exit 1
    }
}

# Step 1: probing only (no env, no hook, no pkg-config candidate reachable).
mkdir -p "$MODDIR/mk"
cat > "$MODDIR/mk/pre.mk" <<EOF
_TOOL_PREFIXES = $ROOT/fake/p_probe/bin
EOF
build_and_check probe

# Step 2: add pkg-config -- must now win over probing.
export PKG_CONFIG_PATH="$ROOT/fake/p_pkg/lib/pkgconfig"
build_and_check pkg

# Step 3: add a mk/ hook -- must now win over pkg-config (and probing).
cat > "$MODDIR/mk/pre.mk" <<EOF
_TOOL_PREFIXES = $ROOT/fake/p_probe/bin
IMPORT_PREFIX = $ROOT/fake/p_hook
EOF
build_and_check hook

# Step 4: add the env/CLI override -- must now win over everything.
export GREET3_PREFIX="$ROOT/fake/p_env"
build_and_check env

echo "import-libraries-precedence OK"
