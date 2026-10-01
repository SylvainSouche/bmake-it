#!/bin/sh
# header-only-import-req: IMPORT_LIB=none declares a header-only
# import -- no lib<LIB>.{a,so,dylib} exists anywhere for it, by design.
# Found in real use: glm has no .pc file at all, so step 4's existing
# lib-file probe fails outright for a genuinely header-only install
# (MacPorts' own optional compiled glm lib only made it work by
# accident); IMPORT=pkg:glm couldn't express "just the headers, no
# library" at all. Proven here with a .pc file whose own Libs: field
# names a library that doesn't exist anywhere -- if IMPORT_LIB=none
# didn't actually suppress lib-staging, this build would fail trying
# (and failing) to find it; instead it must stage only the header and
# build clean.
set -eu
ROOT=$(pwd)
FAKE="$ROOT/fake/fakepkg"

mkdir -p "$FAKE/include/glm" "$FAKE/lib/pkgconfig"
cat > "$FAKE/include/glm/glm.hpp" <<'EOF'
#ifndef GLM_HPP
#define GLM_HPP
inline int glm_version(void) { return 1; }
#endif
EOF

cat > "$FAKE/lib/pkgconfig/glm.pc" <<EOF
prefix=$FAKE
includedir=\${prefix}/include
libdir=\${prefix}/lib

Name: glm
Description: fake header-only test lib (self-contained, no system package used)
Version: 1.0.3
Cflags: -I\${includedir}
Libs: -L\${libdir} -lglm-does-not-exist-3f8a2b
EOF

export PKG_CONFIG_PATH="$FAKE/lib/pkgconfig"

# A header-only import has no LIBS= of its own to declare an ordering
# dependency on (nothing to link) -- build libglm.m first explicitly,
# same as this project's own module-order discovery would need a real
# LIBS= to infer; this is a property of "no LIBS= needed", not
# something this fix is expected to solve.
cd ws
( cd Fw/libglm.m && bmake >../../libglm_build.log 2>&1 && bmake copy-up >>../../libglm_build.log 2>&1 )
bmake >build1.log 2>&1
bin=$(find . -type f -name app | head -1)
[ -n "$bin" ]
out=$("$bin")
echo "$out" | grep -q "^1$"

grep -q "no resolved library directory" build1.log

echo "header-only-import OK"
