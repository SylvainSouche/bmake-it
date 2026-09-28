#!/bin/sh
# requires-software-prereq-req: REQUIRES=<name> [<name> ...] declares
# external prerequisite software a module needs already installed --
# not fetched/imported/staged by Bmake It, just checked. Each name is
# tried via `pkg-config --exists` first, then `command -v` as a
# fallback for a CLI-tool-style prerequisite. A missing one is a clean,
# parse-time failure naming the module and which entry couldn't be
# found, before any build work starts -- proven here by the build never
# even reaching the compile step.
set -eu
ROOT=$(pwd)
FAKE="$ROOT/fake/fakepkg"

cat > "$FAKE/lib/pkgconfig/reqlib.pc" <<EOF
prefix=$FAKE
Name: reqlib
Description: fake test lib, presence-only (self-contained, no system package used)
Version: 1.0
Cflags:
Libs:
EOF

# A fake CLI tool for the command -v fallback path -- pkg-config has no
# .pc file for this, so REQUIRES= must fall through to PATH search.
cat > "$ROOT/fake/bin/reqtool" <<'EOF'
#!/bin/sh
echo "fake reqtool"
EOF
chmod +x "$ROOT/fake/bin/reqtool"

export PKG_CONFIG_PATH="$FAKE/lib/pkgconfig"
export PATH="$ROOT/fake/bin:$PATH"

# --- positive case: both REQUIRES= entries are present -------------------
cat > "$ROOT/ws/Fw/app.m/makefile" <<'EOF'
PROG=app
REQUIRES=reqlib reqtool
.include <mk.prog.mk>
EOF

cd ws
bmake >build1.log 2>&1
bin=$(find . -type f -name app | head -1)
[ -n "$bin" ]
"$bin"

# --- negative case: a third, genuinely missing entry --------------------
cat > Fw/app.m/makefile <<'EOF'
PROG=app
REQUIRES=reqlib reqtool this-tool-does-not-exist-anywhere-3f8a2b
.include <mk.prog.mk>
EOF

cd Fw/app.m
bmake clean >/dev/null 2>&1
if bmake all 2>err.log; then
    echo "expected REQUIRES= with a missing entry to fail the build" >&2
    exit 1
fi
grep -q "REQUIRES=this-tool-does-not-exist-anywhere-3f8a2b" err.log
grep -q "not found via pkg-config or on PATH" err.log
# Fails at parse time -- no compile was ever attempted.
if grep -q "main.o" err.log; then
    echo "expected the failure before any compile step, but one was attempted" >&2
    exit 1
fi

echo "requires-prereq-software OK"
