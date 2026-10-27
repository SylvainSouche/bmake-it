#!/bin/sh
# staging-skip-checks-outputs-req: import staging is skipped only while
# everything it staged is still in place. Found in real use (OpenRider,
# 2026-10-27): the framework's build/<key>/include/ was recreated without
# GLFW's headers, the module's staging fingerprint survived, staging was
# skipped and imgui failed to compile with nothing saying why. Both staging
# paths: an IMPORT=pkg: prefix import (header-only glm) and a fetch: import's
# headers (fakelib). Build, wipe the framework's staged include/, build again:
# the headers come back, and the build says which file was gone. A third,
# unchanged build stages nothing (the skip itself still works).
set -eu
. "$BMK_TESTLIB"
ROOT=$(pwd)

sha256() {
    (sha256sum "$1" 2>/dev/null || shasum -a 256 "$1" 2>/dev/null) | awk '{print $1}'
}

# --- a header-only pkg-config import ------------------------------------------
FAKE="$ROOT/fake/fakepkg"
mkdir -p "$FAKE/include/glm" "$FAKE/lib/pkgconfig"
printf '#ifndef GLM_HPP\n#define GLM_HPP\nstatic inline int glm_version(void) { return 1; }\n#endif\n' > "$FAKE/include/glm/glm.hpp"
cat > "$FAKE/lib/pkgconfig/glm.pc" <<EOF
prefix=$FAKE
includedir=\${prefix}/include
Name: glm
Description: fake header-only test lib
Version: 1.0
Cflags: -I\${includedir}
EOF
export PKG_CONFIG_PATH="$FAKE/lib/pkgconfig"

# --- a fetch: import with a staged header ---------------------------------------
mkdir -p "$ROOT/fake/upstream/fakelib-1.0" "$ROOT/fake/dist"
printf '#ifndef FAKELIB_GREET_H\n#define FAKELIB_GREET_H\nconst char *fakelib_greet(void);\n#endif\n' > "$ROOT/fake/upstream/fakelib-1.0/greet.h"
printf '#include "greet.h"\nconst char *fakelib_greet(void) { return "fakelib"; }\n' > "$ROOT/fake/upstream/fakelib-1.0/greet.c"
( cd "$ROOT/fake/upstream" && tar czf "$ROOT/fake/dist/fakelib-1.0.tar.gz" fakelib-1.0 )
mkdir -p "$ROOT/ws/Fw/libfakelib.m"
printf 'SHA256 (fakelib-1.0.tar.gz) = %s\n' "$(sha256 "$ROOT/fake/dist/fakelib-1.0.tar.gz")" > "$ROOT/ws/Fw/libfakelib.m/distinfo"
cat > "$ROOT/ws/Fw/libfakelib.m/makefile" <<EOF
LIB=fakelib
IMPORT=fetch:fakelib
FETCH_URL=file://$ROOT/fake/dist/fakelib-1.0.tar.gz
SRCS=greet.c
IMPORT_HEADERS=greet.h
.include <mk.lib.mk>
EOF

cd ws
build() {  # build <log>: the header-only module first (it has no LIBS= edge), then all
    ( cd Fw/libglm.m && bmake && bmake copy-up ) >"$1" 2>&1
    bmake >>"$1" 2>&1 || { echo "build failed ($1):" >&2; tail -20 "$1" >&2; exit 1; }
}
build build1.log
KEY=$(bmake -V '${OS_ARCH}')
INC="Fw/build/$KEY/include"
[ -f "$INC/glm/glm.hpp" ] && [ -f "$INC/greet.h" ]
bin=$(find . -type f -name "$(prog_name app)" | head -1)
with_libdir "$(prog_libdir "$bin")" "$bin" | grep -q "^1 fakelib$"

# --- the framework's staged include/ is recreated without the imports' headers;
# each module's staging fingerprint survives -------------------------------------
rm -rf "$INC"; mkdir -p "$INC"
rm -rf Fw/app.m/build                   # app must compile again against them
build build2.log
[ -f "$INC/glm/glm.hpp" ] || { echo "glm's headers were not staged again" >&2; exit 1; }
[ -f "$INC/greet.h" ]     || { echo "fakelib's header was not staged again" >&2; exit 1; }
grep -q "IMPORT=pkg:glm: staged .*glm is gone" build2.log \
    || { echo "no message naming glm's missing staged header:" >&2; cat build2.log >&2; exit 1; }
grep -q "IMPORT=fetch:fakelib: staged .*greet.h is gone" build2.log \
    || { echo "no message naming fakelib's missing staged header:" >&2; cat build2.log >&2; exit 1; }
with_libdir "$(prog_libdir "$bin")" "$bin" | grep -q "^1 fakelib$"

# --- nothing gone, nothing changed: staging is skipped, silently ------------------
build build3.log
if grep -qE "staged header|is gone|resolved via" build3.log; then
    echo "an unchanged build staged again:" >&2; grep -E "staged header|is gone|resolved via" build3.log >&2; exit 1
fi

echo "restage-missing-staged-outputs OK"
