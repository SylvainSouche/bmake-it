#!/bin/sh
# fetch-root-include-req: the resolved work tree's own root is on the
# include search path automatically, so a nested SRCS= entry can
# #include a root header with a plain quote-include, with no hand-
# written mk/ hook -- mirrors Dear ImGui's own real layout exactly
# (backends/*.cpp #include "imgui.h" from the tree root). Found in real
# use: it only ever worked by accident once an earlier build had
# already staged imgui.h into the framework's own public include dir,
# masking the gap on every incremental build after the first -- proven
# here on a genuinely fresh, first extraction (no prior build to mask
# anything).
set -eu
ROOT=$(pwd)

sha256() {
    (sha256sum "$1" 2>/dev/null || shasum -a 256 "$1" 2>/dev/null) | awk '{print $1}'
}

mkdir -p "$ROOT/fake/upstream/imgui-1.0/backends"
cat > "$ROOT/fake/upstream/imgui-1.0/imgui.h" <<'EOF'
#ifndef IMGUI_H
#define IMGUI_H
const char *imgui_core(void);
#endif
EOF
cat > "$ROOT/fake/upstream/imgui-1.0/imgui.cpp" <<'EOF'
#include "imgui.h"
const char *imgui_core(void) { return "core"; }
EOF
cat > "$ROOT/fake/upstream/imgui-1.0/backends/imgui_impl_glfw.cpp" <<'EOF'
#include "imgui.h"
const char *imgui_glfw(void) { return "glfw"; }
EOF
mkdir -p "$ROOT/fake/dist"
( cd "$ROOT/fake/upstream" && tar czf "$ROOT/fake/dist/imgui-1.0.tar.gz" imgui-1.0 )
HASH=$(sha256 "$ROOT/fake/dist/imgui-1.0.tar.gz")
cat > "$ROOT/ws/Fw/libimgui.m/distinfo" <<EOF
SHA256 (imgui-1.0.tar.gz) = $HASH
EOF
cat > "$ROOT/ws/Fw/libimgui.m/makefile" <<EOF
LIB=imgui
IMPORT=fetch:imgui
FETCH_URL=file://$ROOT/fake/dist/imgui-1.0.tar.gz
SRCS=imgui.cpp backends/imgui_impl_glfw.cpp
IMPORT_HEADERS=imgui.h
.include <mk.lib.mk>
EOF

cd ws
bmake >build1.log 2>&1
grep -q "imgui_impl_glfw.cpp" build1.log
find . -path "*libimgui.m/build/*/lib/libimgui*" | grep -q .

echo "fetch-root-include OK"
