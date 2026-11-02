#!/bin/sh
# import-dll-staged-req. An imported Windows library whose DLL has another name
# than its import library, and lives elsewhere: the DLL is found through the
# import library and staged, so the program starts. If it cannot be found, the
# build says which DLL is missing. No DLLs elsewhere; MSVC output makes its own.
set -eu
. "$BMK_TESTLIB"
[ "$BMK_T_OS" = win ] || exit 77
root=$(pwd)

mkdir -p ws/Fw/libzed.m ws/Fw/app.m/src
printf 'PARENT_WS=\n.include "mk.workspace.mk"\n' > ws/makefile
printf 'PREREQS=\n.include <mk.framework.mk>\n' > ws/Fw/makefile
cd ws
[ "$(bmake -C Fw -V _BMK_MSVC_ABI 2>/dev/null)" != yes ] || exit 77
printf 'PROG=app\nLIBS=zed\n.include <mk.prog.mk>\n' > Fw/app.m/makefile
cat > Fw/app.m/src/main.c <<'EOF'
#include <stdio.h>
int zed_fn(void);
int main(void) { printf("got %d\n", zed_fn()); return 0; }
EOF

# --- a package as mingw-w64 lays them out: lib/libzed.dll.a, bin/zed-1.dll ----------
printf 'PROG=probe\n.include <mk.prog.mk>\n' > Fw/libzed.m/makefile
cc=$(bmake -C Fw/libzed.m -V '${CC}')
rm Fw/libzed.m/makefile
mkdir -p "$root/pkg/zed-1.0/lib" "$root/pkg/zed-1.0/bin"
echo 'int zed_fn(void) { return 7; }' > "$root/pkg/zed.c"
$cc -shared "$root/pkg/zed.c" -o "$root/pkg/zed-1.0/bin/zed-1.dll" \
    -Wl,--out-implib,"$root/pkg/zed-1.0/lib/libzed.dll.a" >"$root/pkg.log" 2>&1 || {
    cat "$root/pkg.log" >&2; echo "could not make the package" >&2; exit 1; }

pack() { # the module importing the package as it now is
    ( cd "$root/pkg" && tar czf zed-1.0.tar.gz zed-1.0 )
    hash=$( (sha256sum "$root/pkg/zed-1.0.tar.gz" 2>/dev/null || shasum -a 256 "$root/pkg/zed-1.0.tar.gz") | awk '{print $1}')
    printf 'SHA256 (zed-1.0.tar.gz) = %s\n' "$hash" > Fw/libzed.m/distinfo
    cat > Fw/libzed.m/makefile <<EOF
LIB=zed
IMPORT=fetch-bin:zed
FETCH_URL=file://$root/pkg/zed-1.0.tar.gz
.include <mk.lib.mk>
EOF
}
pack
bmake >build.log 2>&1 || { cat build.log >&2; exit 1; }
find Fw -name zed-1.dll | grep -q . || { cat build.log >&2; echo "zed-1.dll was not staged" >&2; exit 1; }
bin=$(find Fw/build -type f -name "$(prog_name app)" | head -1)
out=$(with_libdir "$(prog_libdir "$bin")" "$bin" | tr -d '\r')
[ "$out" = 'got 7' ] || { echo "expected 'got 7', got [$out]" >&2; exit 1; }
! grep -q 'needs zed-1.dll' build.log || { cat build.log >&2; echo "no note when the DLL was found" >&2; exit 1; }

# --- beside the import library, as CMake on Cygwin installs it -----------------------
mv "$root/pkg/zed-1.0/bin/zed-1.dll" "$root/pkg/zed-1.0/lib/zed-1.dll"
pack
bmake clean >/dev/null 2>&1; rm -rf Fw/libzed.m/work Fw/libzed.m/distfiles
bmake >build.log 2>&1 || { cat build.log >&2; exit 1; }
find Fw -path '*/lib/zed-1.dll' | grep -q . || { cat build.log >&2; echo "zed-1.dll beside the import library was not staged" >&2; exit 1; }

# --- nowhere: the build still works, and names what the program will need ----------------
rm "$root/pkg/zed-1.0/lib/zed-1.dll"
pack
bmake clean >/dev/null 2>&1; rm -rf Fw/libzed.m/work Fw/libzed.m/distfiles
bmake >build.log 2>&1 || { cat build.log >&2; exit 1; }
grep -q 'libzed.dll.a needs zed-1.dll' build.log || { cat build.log >&2; echo "the missing DLL must be named" >&2; exit 1; }

echo "import-dll-staged OK"
