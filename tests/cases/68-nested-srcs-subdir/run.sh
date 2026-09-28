#!/bin/sh
# nested-srcs-objdir-req: a SRCS= entry naming a nested path compiles
# correctly on a first build, through IMPORT=fetch:'s own extraction
# pipeline (the exact path that broke: _fetch_import:'s rm -rf/mkdir -p
# ${_OBJDIR} on a genuine extraction only recreated the TOP-LEVEL object
# dir, so a source under a subdirectory -- like Dear ImGui's own
# backends/ -- had nowhere to write its .o). Mirrors ImGui's own layout:
# a top-level source plus one under backends/.
set -eu
ROOT=$(pwd)

sha256() {
    (sha256sum "$1" 2>/dev/null || shasum -a 256 "$1" 2>/dev/null) | awk '{print $1}'
}

mkdir -p "$ROOT/fake/upstream/nested-1.0/backends"
cat > "$ROOT/fake/upstream/nested-1.0/core.h" <<'EOF'
#ifndef CORE_H
#define CORE_H
const char *core_msg(void);
#endif
EOF
cat > "$ROOT/fake/upstream/nested-1.0/core.c" <<'EOF'
#include "core.h"
const char *core_msg(void) { return "core"; }
EOF
cat > "$ROOT/fake/upstream/nested-1.0/backends/backend.h" <<'EOF'
#ifndef BACKEND_H
#define BACKEND_H
const char *backend_msg(void);
#endif
EOF
cat > "$ROOT/fake/upstream/nested-1.0/backends/backend.c" <<'EOF'
#include "backend.h"
const char *backend_msg(void) { return "backend"; }
EOF

mkdir -p "$ROOT/fake/dist"
( cd "$ROOT/fake/upstream" && tar czf "$ROOT/fake/dist/nested-1.0.tar.gz" nested-1.0 )
HASH=$(sha256 "$ROOT/fake/dist/nested-1.0.tar.gz")

mkdir -p "$ROOT/ws/Fw/libnested.m"
cat > "$ROOT/ws/Fw/libnested.m/distinfo" <<EOF
SHA256 (nested-1.0.tar.gz) = $HASH
EOF
cat > "$ROOT/ws/Fw/libnested.m/makefile" <<EOF
LIB=nested
IMPORT=fetch:nested
FETCH_URL=file://$ROOT/fake/dist/nested-1.0.tar.gz
SRCS=core.c backends/backend.c
IMPORT_HEADERS=core.h
.include <mk.lib.mk>
EOF

mkdir -p "$ROOT/ws/Fw/app.m/src"
cat > "$ROOT/ws/Fw/app.m/makefile" <<'EOF'
PROG=app
LIBS=nested
.include <mk.prog.mk>
EOF
cat > "$ROOT/ws/Fw/app.m/src/main.c" <<'EOF'
#include <stdio.h>
#include "core.h"
const char *backend_msg(void);
int main(void) { printf("%s %s\n", core_msg(), backend_msg()); return 0; }
EOF

cd ws
bmake >build1.log 2>&1
bin=$(find . -type f -name app | head -1)
[ -n "$bin" ]
out=$("$bin")
echo "$out" | grep -q "core backend"

# The nested object landed in its own subdirectory, not flattened or
# dropped.
find . -path "*libnested.m/build/*/obj/backends/backend.o" | grep -q .

echo "nested-srcs-subdir OK"
