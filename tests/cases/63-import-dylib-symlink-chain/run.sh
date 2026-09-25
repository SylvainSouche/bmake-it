#!/bin/sh
# import-staging-req: a real macOS dylib install lays out a symlink
# chain with the version BEFORE the extension (libfoo.dylib ->
# libfoo.34.dylib -> libfoo.34.3.5.dylib), unlike ELF's libfoo.so ->
# libfoo.so.34 -> libfoo.so.34.3.5 (version AFTER). _stage_import:
# used to glob lib<LIB>.<ext>* anchored on the search extension, which
# only ever matched the unversioned dylib name and copied it verbatim
# via cp -a -- staging a dangling symlink (its real target's name never
# matched the glob) or, for an absolute-target symlink, one pointing
# back into the original prefix instead of the staged build tree. Real
# packages laid out this way (PDAL, GDAL, GLFW on macOS) hit this.
# Proven here by actually loading and running the linked binary, not
# just by inspecting the staged files -- a broken symlink still passes
# a naive "file exists" check.
set -eu
if [ "$(uname -s)" != "Darwin" ]; then
    echo "skip: macOS-specific dylib symlink-chain layout" >&2
    exit 77
fi
ROOT=$(pwd)
FAKE="$ROOT/fake/fakepkg"

CC=${CC:-cc}
"$CC" -dynamiclib -install_name @rpath/libfoo.34.dylib \
    -current_version 34.3.5 -compatibility_version 34 \
    -o "$FAKE/lib/libfoo.34.3.5.dylib" "$ROOT/fake/fakesrc/impl.c"
ln -s libfoo.34.3.5.dylib "$FAKE/lib/libfoo.34.dylib"
ln -s libfoo.34.dylib "$FAKE/lib/libfoo.dylib"

cat > "$FAKE/lib/pkgconfig/foo.pc" <<EOF
prefix=$FAKE
includedir=\${prefix}/include
libdir=\${prefix}/lib

Name: foo
Description: fake test lib with a real macOS dylib symlink chain
Version: 34.3.5
Cflags: -I\${includedir}
Libs: -L\${libdir} -lfoo
EOF

export PKG_CONFIG_PATH="$FAKE/lib/pkgconfig"

cd ws
bmake >build1.log 2>&1

libdir=$(find . -type d -path "*Fw/build/*/lib" | head -1)
[ -n "$libdir" ]

# The unversioned name AND the SONAME-equivalent major-version name must
# both be staged as valid (non-dangling) symlinks -- -lfoo needs the
# former at link time, dyld's embedded @rpath/libfoo.34.dylib needs the
# latter at load time. Neither may point outside the staged tree.
for name in libfoo.dylib libfoo.34.dylib; do
    [ -L "$libdir/$name" ] || { echo "expected $name to be staged as a symlink" >&2; exit 1; }
    target=$(readlink "$libdir/$name")
    case "$target" in
        /*) echo "$name symlink leaked an absolute path: $target" >&2; exit 1 ;;
    esac
    [ -e "$libdir/$name" ] || { echo "$name is a dangling symlink (target: $target)" >&2; exit 1; }
done
[ -f "$libdir/libfoo.34.3.5.dylib" ]

bin=$(find . -type f -name app | head -1)
[ -n "$bin" ]
out=$("$bin")
echo "$out" | grep -q "hello from real macos-style symlinked dylib"

echo "import-dylib-symlink-chain OK"
