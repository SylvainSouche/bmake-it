#!/bin/sh
# staging-symlink-chain-real-file-req (lasviewer round 6, item 3): a distro
# installs libglfw.so -> libglfw.so.3 -> libglfw.so.3.3 -> the real file in
# /usr/lib/<triple>/ -- every entry in the import's lib/ is a symlink and
# the real file is in ANOTHER directory. Staging used to link the real
# file's own name to itself (libglfw.so.3.3 -> libglfw.so.3.3) because the
# real file matched no glob in the resolved libdir and so was never copied;
# the build then failed with "prerequisite library glfw ... has not been
# built yet". Built here for the host's own shared-library naming.
set -eu
. "$BMK_TESTLIB"
# A versioned symlink chain is an ELF/macOS layout: a Windows DLL carries its
# version inside the file and has no such chain (windows-shlib-versioninfo-
# uniform-naming-req), so there is nothing to test there.
if [ "$BMK_T_OS" = win ]; then echo "skip: no versioned shared-library symlink chains on Windows" >&2; exit 77; fi
ROOT=$(pwd)
P="$ROOT/fake/prefix"
CC=${CC:-cc}
if [ "$(uname -s)" = Darwin ]; then
    REAL=libchain.2.1.dylib; MID=libchain.2.dylib; TOP=libchain.dylib
    "$CC" -dynamiclib -install_name "@rpath/$MID" -o "$ROOT/fake/real/$REAL" "$ROOT/fake/impl.c"
else
    REAL=libchain.so.2.1; MID=libchain.so.2; TOP=libchain.so
    "$CC" -shared -fPIC -Wl,-soname,"$MID" -o "$ROOT/fake/real/$REAL" "$ROOT/fake/impl.c"
fi
# Every entry in the prefix's lib/ is a symlink; the real file is elsewhere.
ln -s "$ROOT/fake/real/$REAL" "$P/lib/$REAL"
ln -s "$REAL" "$P/lib/$MID"
ln -s "$MID" "$P/lib/$TOP"

printf 'LIB=chain\nIMPORT=prefix:%s\nIMPORT_HEADERS=chain\n.include <mk.lib.mk>\n' "$P" > ws/Fw/libchain.m/makefile

cd ws
bmake >build1.log 2>&1
bin=$(find . -type f -name "$(prog_name app)" | head -1)
[ -n "$bin" ]
"$bin" | grep -q "^85$"

# The staged lib/ has the real file exactly once, as a regular file, and
# no link points at itself.
staged=$(find . -type d -path "*libchain.m/build/*/lib" | head -1)
[ -n "$staged" ]
[ -f "$staged/$REAL" ] && [ ! -L "$staged/$REAL" ]
for n in "$REAL" "$MID" "$TOP"; do
    if [ -L "$staged/$n" ] && [ "$(readlink "$staged/$n")" = "$n" ]; then
        echo "$n is a symlink to itself" >&2; exit 1
    fi
    [ -e "$staged/$n" ] || { echo "$n dangles or is missing" >&2; exit 1; }
done
echo "staging-symlink-chain OK"
