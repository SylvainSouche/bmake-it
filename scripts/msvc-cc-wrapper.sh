#!/bin/sh
# msvc-cc-wrapper.sh — presents cl.exe/link.exe as a gcc/clang-compatible
# CC/CXX/LD, so mk.prog.mk/mk.lib.mk's recipes (-c, -o, -I, -D, -L, -l,
# -shared, -Wl,--out-implib,...) need no MSVC-specific branches: this
# wrapper is the ONLY place that speaks cl.exe's /Fo, /Fe:, /I, /D,
# /LIBPATH:, /DLL, /IMPLIB: syntax, and the only place that translates
# Cygwin POSIX paths to Windows paths (cl.exe/link.exe are native Win32
# programs, not Cygwin-aware) via `cygpath -w`.
#
# Precondition (documented, not enforced here): cl.exe must already be on
# PATH -- i.e. bmake was launched from a Cygwin shell with the Visual
# Studio developer environment already active (INCLUDE/LIB/PATH set, e.g.
# via vcvarsall.bat or a "Developer Command Prompt"), same expectation as
# "clang must be on PATH" for TOOLCHAIN=llvm. No vcvarsall auto-bootstrap
# is attempted -- untestable from here and a well-documented, standard
# precondition for any Cygwin+MSVC workflow.
#
# @impl 0f87-6a98-96de-1865
set -eu

mode=link          # flipped to 'compile' on -c
building_dll=no    # flipped to yes on -shared
out=""
cflags=""          # /I, /D, /Z7 etc -- go before the source/object list
sources=""         # translated positional .c/.cc/.cpp/.o/.obj paths
linkflags=""        # /LIBPATH:, .lib names, /DLL, /IMPLIB: -- go after /link

winpath() {
    cygpath -w "$1"
}

while [ $# -gt 0 ]; do
    arg=$1
    case "$arg" in
        -c)
            mode=compile
            ;;
        -o)
            shift
            out=$1
            ;;
        -o*)
            out=${arg#-o}
            ;;
        -I)
            shift
            cflags="$cflags /I\"$(winpath "$1")\""
            ;;
        -I*)
            cflags="$cflags /I\"$(winpath "${arg#-I}")\""
            ;;
        -D*)
            # -D<name>[=<val>] has no path component -- forward verbatim.
            cflags="$cflags /${arg#-}"
            ;;
        -g)
            cflags="$cflags /Zi /FS"
            ;;
        -O0)
            cflags="$cflags /Od"
            ;;
        -O1|-O2|-O3)
            cflags="$cflags /O2"
            ;;
        -fPIC)
            # No-op on Windows -- position independence isn't a compile-time
            # opt-in the way it is on ELF; every image is relocatable by
            # default (ASLR-capable) unless explicitly disabled.
            ;;
        -shared)
            building_dll=yes
            linkflags="$linkflags /DLL"
            ;;
        -Wl,--out-implib,*)
            implib=${arg#-Wl,--out-implib,}
            linkflags="$linkflags /IMPLIB:\"$(winpath "$implib")\""
            ;;
        -L)
            shift
            linkflags="$linkflags /LIBPATH:\"$(winpath "$1")\""
            ;;
        -L*)
            linkflags="$linkflags /LIBPATH:\"$(winpath "${arg#-L}")\""
            ;;
        -l*)
            # MSVC has no -lname convention: link.exe resolves a bare
            # "name.lib" against /LIBPATH: dirs itself, so just append the
            # extension -- no path translation, it's a name, not a path.
            linkflags="$linkflags ${arg#-l}.lib"
            ;;
        *.c|*.cc|*.cpp|*.cxx|*.o|*.obj|*.lib|*.dll)
            sources="$sources \"$(winpath "$arg")\""
            ;;
        *)
            # Unrecognized flag: forward as-is rather than silently drop it.
            cflags="$cflags $arg"
            ;;
    esac
    shift
done

if [ "$mode" = "compile" ]; then
    [ -n "$out" ] || { echo "msvc-cc-wrapper: -c given with no -o output" >&2; exit 1; }
    eval "cl.exe /nologo /c $cflags $sources /Fo\"$(winpath "$out")\""
else
    [ -n "$out" ] || { echo "msvc-cc-wrapper: link mode with no -o output" >&2; exit 1; }
    if [ "$building_dll" = "yes" ]; then
        # /Fe: still names cl's own output for consistency/diagnostics;
        # the authoritative name for a DLL link is /OUT: after /link.
        eval "cl.exe /nologo $cflags $sources /link $linkflags /OUT:\"$(winpath "$out")\""
    else
        eval "cl.exe /nologo $cflags $sources /Fe:\"$(winpath "$out")\" /link $linkflags"
    fi
fi
