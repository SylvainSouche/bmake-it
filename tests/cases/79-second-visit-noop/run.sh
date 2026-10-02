#!/bin/sh
# framework-dir-creation-ordering-fix-req / import-staging-idempotent-req /
# linkdeps-write-idempotent-req (lasviewer round 4, items 2 and 3).
# (a) A clean build of a workspace with a static library must archive it
#     exactly once and print no "copy-up collision": build/<key>/include
#     used to appear only after the first framework pass, so the second
#     pass compiled with an extra -I, changed the inputs hash, recompiled
#     and re-archived (new embedded ar timestamp -> copy differs).
# (b) A second, unchanged `bmake` must write no file under any build/
#     (find -newer a stamp) and print no "staged"/"imported"/"resolved
#     via" lines for the imported module.
set -eu
ROOT=$(pwd)
FAKE="$ROOT/fake/fakepkg"

CC=${CC:-cc}
"$CC" -c "$ROOT/fake/fakesrc/impl.c" -o "$ROOT/fake/fakesrc/impl.o"
ar rcs "$FAKE/lib/libgreet2.a" "$ROOT/fake/fakesrc/impl.o"
cat > "$FAKE/lib/pkgconfig/greet2.pc" <<PCEOF
prefix=$FAKE
includedir=\${prefix}/include
libdir=\${prefix}/lib

Name: greet2
Description: fake test lib
Version: 3.1.4
Cflags: -I\${includedir}
Libs: -L\${libdir} -lgreet2
PCEOF
export PKG_CONFIG_PATH="$FAKE/lib/pkgconfig"

cd ws
bmake >build1.log 2>&1
bin=$(find . -type f -name app | head -1)
[ -n "$bin" ]
"$bin" | grep -q "hello from fake pkg-config import 7"

n=$(grep -c "^ar rcs .*libgeo.a" build1.log || true)
[ "$n" = "1" ] || { echo "libgeo.a archived $n times, expected 1" >&2; exit 1; }
if grep -q "copy-up collision" build1.log; then
    echo "unexpected copy-up collision on a clean build" >&2
    exit 1
fi

sleep 1
touch ../stamp
sleep 1
bmake >build2.log 2>&1

if grep -qE "staged header|resolved via|===> imported" build2.log; then
    echo "second unchanged build re-ran import staging:" >&2
    grep -E "staged header|resolved via|===> imported" build2.log >&2
    exit 1
fi
if grep -qE "^(/[^ ]*clang|/[^ ]*gcc|cc|ar rcs)" build2.log; then
    echo "second unchanged build ran a compiler/archiver" >&2
    exit 1
fi
changed=$(find . -path '*/build/*' -type f -newer ../stamp ! -name '*.log' ! -path '*/runs/*' | head -5)
if [ -n "$changed" ]; then
    echo "second unchanged build wrote files under build/:" >&2
    echo "$changed" >&2
    exit 1
fi

echo "second-visit-noop OK"
