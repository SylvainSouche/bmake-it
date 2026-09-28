#!/bin/sh
# relink-on-libs-change-req: a program's link step must depend on the
# actual resolved file of every LIBS= entry, not just -l/-L flags, so a
# library rebuilt in ANOTHER framework triggers a real relink. Found in
# real use (lasviewer): a stale binary kept passing because nothing in
# the prerequisite graph ever changed when a cross-framework static
# library did -- proven here by rebuilding ONLY the library module
# directly (never touching app.m's own sources) and confirming the
# rebuilt app.m actually relinks and picks up the new content, not by
# rebuilding the whole workspace (which would rebuild everything anyway
# and could pass even with the bug present).
set -eu
ROOT=$(pwd)

cd ws
bmake >build1.log 2>&1
# The module's OWN binary, not a framework-level copy-up -- only app.m's
# own bmake invocations run below, so only its own build/ output is
# guaranteed fresh; a framework/workspace-level copy would stay stale
# regardless of the fix under test, and checking it would prove nothing.
bin="Fw2/app.m/build/macos-arm64/bin/app"
[ -x "$bin" ]
out1=$("$bin")
echo "$out1" | grep -q "v1"

# Change the library's source and rebuild ONLY the library module (and
# its copy-up into the framework) -- app.m's own directory is never
# touched, so if bmake relinks it, that can only be because the
# library's own resolved file is a real prerequisite.
sed -i.bak 's/v1/v2/' Fw1/libfoo.m/src/foo.c
cd Fw1/libfoo.m
bmake >../../lib_rebuild.log 2>&1
bmake copy-up >../../lib_copyup.log 2>&1
cd ../..

cd Fw2/app.m
bmake >app_rebuild.log 2>&1
# The link command itself must have actually run (bmake echoes it,
# unsilenced) -- not silently skipped as "up to date".
grep -q -- "-o .*/bin/app" app_rebuild.log
cd "$ROOT/ws"

out2=$("$bin")
echo "$out2" | grep -q "v2"
if [ "$out1" = "$out2" ]; then
    echo "expected the binary to change after the library it links against was rebuilt" >&2
    exit 1
fi

echo "relink-on-libs-change OK"
