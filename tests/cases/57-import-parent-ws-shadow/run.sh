#!/bin/sh
# imported-libraries-are-ordinary-modules-req: an IMPORT=-based framework
# participates in PARENT_WS/shadowing exactly like a compiled one --
# mirrors the existing prereq-local-shadows-parent case (29), but both
# the parent's and the child's own "Lib" framework use IMPORT= this
# time. A framework present in both the current workspace and a
# PARENT_WS must resolve to the LOCAL one (headers, link, and the
# actual symbol executed), not the parent's.
set -eu
ROOT=$(pwd)
FAKE="$ROOT/fake"
CC=${CC:-cc}

"$CC" -c -I"$FAKE/parent_pkg/include" "$FAKE/src/parent_impl.c" -o "$FAKE/src/parent_impl.o"
ar rcs "$FAKE/parent_pkg/lib/libutil.a" "$FAKE/src/parent_impl.o"
cat > "$FAKE/parent_pkg/lib/pkgconfig/util.pc" <<EOF
prefix=$FAKE/parent_pkg
includedir=\${prefix}/include
libdir=\${prefix}/lib
Name: util
Description: fake test lib, parent copy (self-contained)
Version: 1.0
Cflags: -I\${includedir}
Libs: -L\${libdir} -lutil
EOF

"$CC" -c -I"$FAKE/local_pkg/include" "$FAKE/src/local_impl.c" -o "$FAKE/src/local_impl.o"
ar rcs "$FAKE/local_pkg/lib/libutil.a" "$FAKE/src/local_impl.o"
cat > "$FAKE/local_pkg/lib/pkgconfig/util-local.pc" <<EOF
prefix=$FAKE/local_pkg
includedir=\${prefix}/include
libdir=\${prefix}/lib
Name: util-local
Description: fake test lib, local copy (self-contained)
Version: 1.0
Cflags: -I\${includedir}
Libs: -L\${libdir} -lutil
EOF

export PKG_CONFIG_PATH="$FAKE/parent_pkg/lib/pkgconfig:$FAKE/local_pkg/lib/pkgconfig"

parent=$(CDPATH= cd parent && pwd)
sed "s|@@PARENT@@|$parent|" child/makefile.in > child/makefile

(cd parent/Lib && bmake)
(cd child/Lib && bmake)

cd child
bmake

bin=$(find App -type f -name app | head -1)
[ -n "$bin" ] || { echo "app binary not found" >&2; exit 1; }

localdir=$(find Lib/build -type d -name lib | head -1)
parentdir=$(find "$parent/Lib/build" -type d -name lib | head -1)
[ -n "$localdir" ] && [ -n "$parentdir" ] || { echo "build lib dirs not found" >&2; exit 1; }

out=$(DYLD_LIBRARY_PATH="$localdir" LD_LIBRARY_PATH="$localdir" "$bin")
[ "$out" = "local-lib" ] || { echo "local-only run: expected 'local-lib', got '$out'" >&2; exit 1; }

combined="$localdir:$parentdir"
out=$(DYLD_LIBRARY_PATH="$combined" LD_LIBRARY_PATH="$combined" "$bin")
[ "$out" = "local-lib" ] || { echo "both-present run: expected 'local-lib', got '$out'" >&2; exit 1; }

echo "import-parent-ws-shadow OK ($out)"
