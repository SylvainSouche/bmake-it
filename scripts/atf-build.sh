#!/bin/sh
# atf-build.sh OUTDIR -- builds the ATF Bmake It carries: ATF 0.23's own
# sources (contrib/atf-0.23, as released) with contrib/atf-bmk, using the
# module's compilers. Called by mk.atfbmk.mk, with CC, CXX, AR, TOOLCHAIN
# and ATF_BMK_MODE in the environment:
#   win    a native Windows runtime (TOOLCHAIN=msvc, ABI=mingw), which has no
#          ATF of its own (native-windows-tests-req, atf-for-windows-dec):
#          with the Windows layer, contrib/atf-bmk/win
#   posix  any other target, with BMK_ATF=bundled (bundled-atf-selectable-
#          req): the sources alone, configured by compile probes as ATF's
#          configure would
#
# Writes OUTDIR/libatf-c.a and OUTDIR/libatf-c++.a (TOOLCHAIN=msvc:
# atf-c.lib, atf-c++.lib), every compiler message in OUTDIR/build.log. Built
# once per OUTDIR (a framework's build root) and kept while STAMP matches;
# modules built in parallel wait for the one building it.
# @impl 7854-6ae4-9b5d-8fc8
# @impl 7854-6ae4-bac8-49b6
set -eu

OUT=${1:?usage: atf-build.sh OUTDIR}
MODE=${ATF_BMK_MODE:-posix}
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=$HERE/../contrib/atf-0.23
BMK=$HERE/../contrib/atf-bmk
WIN=$BMK/win
# (rebuilt when the compilers, contrib/atf-bmk or this script change)
STAMP="atf-0.23 $MODE atf-bmk=$(find "$BMK" -type f ! -path '*/tests/*' ! -path '*/expected/*' ! -path '*/test-shim/*' | sort | xargs cat | cksum | cut -d' ' -f1) script=$(cksum < "$0" | cut -d' ' -f1) CC=$CC CXX=$CXX"
case $MODE in
    win)   WHAT="ATF 0.23 for this Windows runtime" ;;
    posix) WHAT="ATF 0.23 (BMK_ATF=bundled)" ;;
    *)     echo "error: atf-build.sh: ATF_BMK_MODE=$MODE -- expected win or posix" >&2; exit 1 ;;
esac

if [ "${TOOLCHAIN:-}" = msvc ]; then
    LIBC=$OUT/atf-c.lib; LIBCXX=$OUT/atf-c++.lib
else
    LIBC=$OUT/libatf-c.a; LIBCXX=$OUT/libatf-c++.a
fi

uptodate() {
    [ -f "$LIBC" ] && [ -f "$LIBCXX" ] && [ -f "$OUT/stamp" ] && [ "$(cat "$OUT/stamp")" = "$STAMP" ]
}
uptodate && exit 0

# One builder at a time; the others wait for it (up to 10 minutes).
mkdir -p "$OUT"
n=0
while ! mkdir "$OUT/.lock" 2>/dev/null; do
    n=$((n + 1))
    if [ $n -gt 600 ]; then
        echo "error: $WHAT: $OUT/.lock has been held for 10 minutes -- another build of it is stuck or was killed; remove $OUT/.lock and build again" >&2
        exit 1
    fi
    sleep 1
done
trap 'rmdir "$OUT/.lock" 2>/dev/null || true' EXIT
uptodate && exit 0

echo "===> building $WHAT (once per framework build root): $OUT"
rm -rf "$OUT/obj" "$OUT/probe" "$LIBC" "$LIBCXX" "$OUT/stamp"
mkdir -p "$OUT/obj"
: > "$OUT/build.log"

# The whole library, in both modes (on Windows, running a program fails
# saying so: atfw-compat.c)
CSRCS="atf-c/build.c atf-c/check.c atf-c/error.c atf-c/tc.c atf-c/tp.c
       atf-c/utils.c atf-c/detail/dynstr.c atf-c/detail/env.c
       atf-c/detail/fs.c atf-c/detail/list.c atf-c/detail/map.c
       atf-c/detail/process.c atf-c/detail/sanity.c atf-c/detail/text.c
       atf-c/detail/tp_main.c"
CXXSRCS="atf-c++/build.cpp atf-c++/check.cpp atf-c++/tests.cpp
         atf-c++/utils.cpp atf-c++/detail/application.cpp
         atf-c++/detail/env.cpp atf-c++/detail/exceptions.cpp
         atf-c++/detail/fs.cpp atf-c++/detail/process.cpp
         atf-c++/detail/text.cpp"
CSTD=""; CXXEH=""; WSRCS=""; WXXSRCS=""

if [ "$MODE" = win ]; then
    # cl.exe gets mixed paths (C:/...): the MSVC wrapper re-reads its
    # arguments through eval, which would eat a backslash.
    if [ "${TOOLCHAIN:-}" = msvc ]; then
        inc() { printf '%s' "-I$(cygpath -m "$1")"; }
        FI="/FI$(cygpath -m "$WIN/atfw-compat.h")"
        CSTD="-std=c11"
        CXXEH="/EHsc"  # ATF's C++ part throws and catches (cl.exe: C4530 without)
        INCS="$(inc "$WIN") $(inc "$WIN/msvc") $(inc "$BMK/include") $(inc "$WIN/include-msvc") $(inc "$SRC")"
        MSVCSRCS="atfw-msvc.c"  # (what MSVC's C runtime lacks and mingw's has)
    else
        inc() { printf '%s' "-I$1"; }
        FI="-include $WIN/atfw-compat.h"
        INCS="$(inc "$WIN") $(inc "$BMK/include") $(inc "$SRC")"
        MSVCSRCS=""
    fi
    CPPFLAGS="$INCS -DHAVE_CONFIG_H $FI"
    # (in place of atf-c/detail/user.c: no uids on Windows)
    WSRCS="atfw-compat.c user.c regex.cpp $MSVCSRCS"
    WXXSRCS="atfw-compat-cxx.cpp"
else
    # config.h as ATF's configure writes it (m4/module-application.m4): a
    # getopt that takes "+" for POSIX behaviour (run), optreset (compile).
    # The rest is left undefined: ATF then takes its portable paths.
    mkdir -p "$OUT/probe"
    {
        echo "/* written by scripts/atf-build.sh (ATF's configure checks) */"
        echo '#define PACKAGE "atf"'
        echo '#define PACKAGE_NAME "Automated Testing Framework"'
        echo '#define PACKAGE_VERSION "0.23"'
        echo '#define PACKAGE_STRING "Automated Testing Framework 0.23"'
        echo '#define PACKAGE_BUGREPORT "freebsd-testing@freebsd.org"'
        echo '#define PACKAGE_COPYRIGHT "Copyright (c) 2007-2012 The NetBSD Foundation, Inc."'
    } > "$OUT/config.h"
    cat > "$OUT/probe/plus.c" <<'EOF'
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
int main(void) {
    int argc = 4, ch, seen_a = 0, seen_plus = 0;
    char *argv[5] = { strdup("conftest"), strdup("-+"), strdup("-a"), strdup("bar"), NULL };
    while ((ch = getopt(argc, argv, "+a:")) != -1) {
        if (ch == 'a') seen_a = 1;
        else if (ch == '+') seen_plus = 1;
    }
    return (seen_a && !seen_plus) ? EXIT_SUCCESS : EXIT_FAILURE;
}
EOF
    cat > "$OUT/probe/optreset.c" <<'EOF'
#include <stdlib.h>
#include <unistd.h>
int main(void) { optreset = 1; return EXIT_SUCCESS; }
EOF
    # shellcheck disable=SC2086
    if $CC "$OUT/probe/plus.c" -o "$OUT/probe/plus" >> "$OUT/build.log" 2>&1 && "$OUT/probe/plus" >> "$OUT/build.log" 2>&1; then
        echo '#define HAVE_GNU_GETOPT 1' >> "$OUT/config.h"
    fi
    # shellcheck disable=SC2086
    if $CC -c "$OUT/probe/optreset.c" -o "$OUT/probe/optreset.o" >> "$OUT/build.log" 2>&1; then
        echo '#define HAVE_OPTRESET 1' >> "$OUT/config.h"
    fi
    # What configure bakes in for atf_check_build_* and the tests that
    # compile ATF's headers (ATF_BUILD_*, ATF_INCLUDEDIR); both are also read
    # from the environment at run time, these are the defaults.
    {
        echo "#define ATF_BUILD_CC \"$CC\""
        echo "#define ATF_BUILD_CFLAGS \"\""
        echo "#define ATF_BUILD_CPP \"$CC -E\""
        echo "#define ATF_BUILD_CPPFLAGS \"-I$OUT/include\""
        echo "#define ATF_BUILD_CXX \"$CXX\""
        echo "#define ATF_BUILD_CXXFLAGS \"\""
        echo "#define ATF_INCLUDEDIR \"$OUT/include\""
    } >> "$OUT/config.h"
    # (build.c reads ATF_BUILD_* without including config.h itself)
    CPPFLAGS="-I$OUT -I$BMK/include -I$SRC -DHAVE_CONFIG_H -include $OUT/config.h"
    CSRCS="$CSRCS atf-c/detail/user.c"
fi

compile() {  # compile <source path> <object> <c|c++>
    extra=""
    if [ "$MODE" = win ]; then
        case "$1" in
            */detail/fs.c)   extra=-DATFW_FS_C ;;
            */tp_main.c)     extra=-DATFW_TP_MAIN_C ;;
            */tests.cpp)     extra=-DATFW_TESTS_CPP ;;
            */atf-c/utils.c) extra=-DATFW_UTILS_C ;;
            */detail/process.c) extra=-DATFW_PROCESS_C ;;
        esac
    fi
    if [ "$3" = c ]; then cc="$CC $CSTD"; else cc="$CXX $CXXEH"; fi
    echo "--- $cc -O1 $CPPFLAGS $extra -c $1 -o $2" >> "$OUT/build.log"
    # shellcheck disable=SC2086
    if ! $cc -O1 $CPPFLAGS $extra -c "$1" -o "$2" >> "$OUT/build.log" 2>&1; then
        echo "error: $WHAT: compiling $(basename "$1") failed with CC=$CC CXX=$CXX -- the compiler's messages:" >&2
        # (the messages of this source only, not the echoed command lines)
        awk -v src="$1" '/^--- / { this = index($0, src) > 0; next } this' "$OUT/build.log" |
            grep -iE 'error|fatal' | head -8 >&2 || true
        echo "       (all of it in $OUT/build.log)" >&2
        exit 1
    fi
}

cobjs=""; cxxobjs=""
for f in $CSRCS; do
    o=$OUT/obj/$(echo "$f" | tr / _).o; compile "$SRC/$f" "$o" c; cobjs="$cobjs $o"
done
for f in $WSRCS; do
    case $f in *.cpp) l=c++ ;; *) l=c ;; esac
    o=$OUT/obj/w_$f.o; compile "$WIN/$f" "$o" $l; cobjs="$cobjs $o"
done
for f in $CXXSRCS; do
    o=$OUT/obj/$(echo "$f" | tr / _).o; compile "$SRC/$f" "$o" c++; cxxobjs="$cxxobjs $o"
done
for f in $WXXSRCS; do
    o=$OUT/obj/w_$f.o; compile "$WIN/$f" "$o" c++; cxxobjs="$cxxobjs $o"
done

# shellcheck disable=SC2086
if ! { $AR rcs "$LIBC" $cobjs && $AR rcs "$LIBCXX" $cxxobjs; } >> "$OUT/build.log" 2>&1; then
    echo "error: $WHAT: archiving the libraries failed with AR=$AR -- see $OUT/build.log" >&2
    tail -5 "$OUT/build.log" >&2
    exit 1
fi
# The public headers, staged as an install would: OUTDIR/include is what a
# test program compiles against (-I), whatever the mode.
rm -rf "$OUT/include"
mkdir -p "$OUT/include/atf-c" "$OUT/include/atf-c++"
cp "$SRC/atf-c.h" "$SRC/atf-c++.hpp" "$OUT/include/"
for h in build check error error_fwd macros tc tp utils; do
    cp "$SRC/atf-c/$h.h" "$OUT/include/atf-c/"
done
cp "$BMK/include/atf-c/defs.h" "$OUT/include/atf-c/"
for h in build check macros tests utils; do
    cp "$SRC/atf-c++/$h.hpp" "$OUT/include/atf-c++/"
done
if [ "$MODE" = win ] && [ "${TOOLCHAIN:-}" = msvc ]; then
    cp "$WIN/include-msvc/unistd.h" "$OUT/include/"  # (MSVC has none)
fi
printf '%s\n' "$STAMP" > "$OUT/stamp"
