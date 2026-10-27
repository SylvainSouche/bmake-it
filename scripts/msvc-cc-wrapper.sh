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

# A failure of this script's own logic (set -e) must not end the build
# with a bare "Error code 1": name it. A failing cl.exe/link.exe has said
# why itself (tool_failed).
orig_args="$*"
tool_failed=""
trap '_rc=$?; if [ "$_rc" -ne 0 ] && [ -z "$tool_failed" ]; then echo "msvc-cc-wrapper: failed (exit $_rc) in its own processing, not in cl.exe -- invoked as: msvc-cc-wrapper.sh $orig_args" >&2; fi' EXIT

mode=link         # flipped to 'compile' on -c
building_dll=no    # flipped to yes on -shared
out=""
cflags=""          # /I, /D, /Z7 etc -- go before the source/object list
sources=""         # translated positional .c/.cc/.cpp/.o/.obj paths
linkflags=""        # /LIBPATH:, .lib names, /DLL, /IMPLIB: -- go after /link
objects=""          # the .o/.obj inputs: what a generated .def exports
own_def=no          # yes when a .def (or -Wl,/DEF:) was given
objdir=""           # the first object's directory: where that .def goes
deps=no             # -MMD/-MD: write a make dependency file (-MF, else <out>.d)
deps_phony=no       # -MP: plus an empty rule per header
depfile=""
srcfile=""          # the (first) source compiled, as given
csources=""         # the .c/.cc/.cpp/.cxx inputs, translated
libinputs=""        # the .lib/.dll inputs, translated
lang=c              # -x c|c++: the language of a source read from stdin
from_stdin=no       # a "-" source
export VSLANG=1033  # cl.exe's messages in English: /showIncludes is parsed

# The MSVC environment mk.toolchain.msvc.mk found (mk.vcvarsall.mk), when it
# had to: handed over in exported variables, not as an `env PATH="..."`
# prefix inside CC -- a CC with quotes and spaces breaks wherever it is
# used unquoted, as `$CC` in a FETCH_BUILD_CMD is (case 65, 2026-10-27).
[ -z "${BMK_MSVC_BIN:-}" ] || PATH="$BMK_MSVC_BIN:$PATH"
[ -z "${BMK_MSVC_INCLUDE:-}" ] || export INCLUDE="$BMK_MSVC_INCLUDE"
[ -z "${BMK_MSVC_LIB:-}" ] || export LIB="$BMK_MSVC_LIB"
sysdirs="${INCLUDE:-}"  # ;-list of Windows dirs whose headers -MMD leaves out

winpath() {
    cygpath -w "$1"
}

while [ $# -gt 0 ]; do
    arg=$1
    case "$arg" in
        -c)
            mode=compile
            ;;
        -E)
            # preprocess only (REQUIRES=header: probes `-x c -E -o /dev/null -`)
            mode=preprocess
            ;;
        -x)
            shift
            lang=$1
            ;;
        -)
            from_stdin=yes
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
        -isystem)
            # a system/vendored include dir, its warnings silenced: cl.exe's
            # /external:I with /external:W0 (it ignored -isystem, D9002, and
            # the header was not found -- case 53, 2026-10-27)
            shift
            cflags="$cflags /external:I\"$(winpath "$1")\" /external:W0"
            sysdirs="$sysdirs;$(winpath "$1")"
            ;;
        -isystem*)
            cflags="$cflags /external:I\"$(winpath "${arg#-isystem}")\" /external:W0"
            sysdirs="$sysdirs;$(winpath "${arg#-isystem}")"
            ;;
        -MMD|-MD)
            deps=yes
            ;;
        -MP)
            deps_phony=yes
            ;;
        -MF)
            shift
            depfile=$1
            ;;
        -MF*)
            depfile=${arg#-MF}
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
        -fsanitize=*)
            # mk.common.mk already rejects any SANITIZE= value other than
            # "address" for TOOLCHAIN=msvc (MSVC's only supported
            # sanitizer) -- cl.exe likely accepts the gcc-style dash
            # spelling directly, but translate explicitly rather than
            # relying on that. Present on both the compile and the
            # link-mode cl.exe invocation ($cflags is used in both), which
            # is what cl.exe's single-driver ASan model expects.
            cflags="$cflags /${arg#-}"
            ;;
        -std=*)
            # cl.exe's own /std: flag already uses the identical
            # "c++17"/"c++20" spelling CXXSTD= does -- no translation
            # table needed, just the switch character.
            cflags="$cflags /std:${arg#-std=}"
            ;;
        -fopenmp)
            cflags="$cflags /openmp"
            ;;
        -Wall)
            # /W4 is the practical MSVC equivalent of gcc/clang's combined
            # -Wall -Wextra -- cl.exe's own /Wall is far noisier (it also
            # enables warnings off by default specifically because they
            # fire constantly in Microsoft's own headers), not a match.
            cflags="$cflags /W4"
            ;;
        -Wextra)
            # No direct MSVC equivalent; /W4 (above) already covers most
            # of what -Wextra adds beyond -Wall. Silently dropped, not
            # forwarded as an unrecognized flag.
            ;;
        -w)
            # Exact match: cl.exe's own "disable all warnings" switch.
            cflags="$cflags /w"
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
        -Wl,/DEF:*|*.def)
            # The module gives its own export list: no generated one.
            own_def=yes
            linkflags="$linkflags /DEF:\"$(winpath "${arg#-Wl,/DEF:}")\""
            ;;
        -lm)
            # The C math library is part of the UCRT under MSVC: there is no
            # m.lib (LNK1181 for a portable LDFLAGS+=-lm, case 78).
            ;;
        -l*)
            # MSVC has no -lname convention: link.exe resolves a bare
            # "name.lib" against /LIBPATH: dirs itself, so just append the
            # extension -- no path translation, it's a name, not a path.
            linkflags="$linkflags ${arg#-l}.lib"
            ;;
        *.o|*.obj)
            # cl.exe warns D9024 "unrecognized source file type" for a .o
            # but needs one input file (D8003): it stays cl's input.
            sources="$sources \"$(winpath "$arg")\""
            objects="$objects \"$(winpath "$arg")\""
            objdir=${objdir:-$(dirname "$arg")}
            ;;
        *.c|*.cc|*.cpp|*.cxx)
            sources="$sources \"$(winpath "$arg")\""
            csources="$csources \"$(winpath "$arg")\""
            srcfile=${srcfile:-$arg}
            ;;
        *.lib|*.dll)
            sources="$sources \"$(winpath "$arg")\""
            libinputs="$libinputs \"$(winpath "$arg")\""
            ;;
        *)
            # Unrecognized flag: forward as-is rather than silently drop it.
            cflags="$cflags $arg"
            ;;
    esac
    shift
done

if [ "$mode" = "preprocess" ]; then
    # cl.exe /E writes to stdout; a "-" source is copied to a file first
    # (cl.exe reads no stdin), named for -x's language.
    if [ "$from_stdin" = yes ]; then
        case "$lang" in c++) ext=cpp ;; *) ext=c ;; esac
        tmpsrc=$(mktemp "${TMPDIR:-/tmp}/bmk-cl.XXXXXX")
        mv "$tmpsrc" "$tmpsrc.$ext"; tmpsrc="$tmpsrc.$ext"
        trap '_rc=$?; rm -f "$tmpsrc"; if [ "$_rc" -ne 0 ] && [ -z "$tool_failed" ]; then echo "msvc-cc-wrapper: failed (exit $_rc) in its own processing, not in cl.exe -- invoked as: msvc-cc-wrapper.sh $orig_args" >&2; fi' EXIT
        cat > "$tmpsrc"
        sources="$sources \"$(winpath "$tmpsrc")\""
    fi
    tool_failed=yes
    if [ -n "$out" ] && [ "$out" != - ]; then
        eval "cl.exe /nologo /E $cflags $sources" > "$out"
    else
        eval "cl.exe /nologo /E $cflags $sources"
    fi
    exit
elif [ "$mode" = "compile" ]; then
    [ -n "$out" ] || { echo "msvc-cc-wrapper: -c given with no -o output" >&2; exit 1; }
    if [ "$deps" = no ]; then
        tool_failed=yes
        eval "cl.exe /nologo /c $cflags $sources /Fo\"$(winpath "$out")\""
        exit
    fi
    # header-dependency-tracking-req under MSVC: -MMD [-MP] [-MF <file>] as
    # gcc/clang do it, from cl.exe's /showIncludes notes -- the headers the
    # source includes, less those under INCLUDE (the toolset's and SDK's)
    # and the -isystem dirs, as -MMD leaves system headers out. The other
    # output (diagnostics) is passed on. Paths are written in POSIX form
    # with spaces escaped, as make reads them.
    # @impl 0f87-6ab5-8442-b2dc
    [ -n "$depfile" ] || depfile="${out%.*}.d"
    rc=0
    clout=$(eval "cl.exe /nologo /showIncludes /c $cflags $sources /Fo\"$(winpath "$out")\"") || rc=$?
    clout=$(printf '%s\n' "$clout" | tr -d '\r')
    printf '%s\n' "$clout" | grep -v '^Note: including file:' || true
    [ "$rc" -eq 0 ] || { tool_failed=yes; exit "$rc"; }
    sysl=$(printf '%s' "$sysdirs" | tr 'A-Z' 'a-z')
    hdrs=$(printf '%s\n' "$clout" | sed -n 's/^Note: including file: *//p' | while IFS= read -r h; do
        hl=$(printf '%s' "$h" | tr 'A-Z' 'a-z')
        skip=no
        _ifs=$IFS; IFS=';'
        for s in $sysl; do
            [ -n "$s" ] || continue
            case "$hl" in "${s%\\}"\\*) skip=yes; break ;; esac
        done
        IFS=$_ifs
        [ "$skip" = yes ] || printf '%s\n' "$h"
    done | sort -u | cygpath -u -f - | sed 's/ /\\ /g')
    {
        printf '%s: %s' "$out" "$(printf '%s' "$srcfile" | sed 's/ /\\ /g')"
        printf '%s\n' "$hdrs" | while IFS= read -r h; do if [ -n "$h" ]; then printf ' \\\n  %s' "$h"; fi; done
        printf '\n'
        if [ "$deps_phony" = yes ]; then
            printf '%s\n' "$hdrs" | while IFS= read -r h; do if [ -n "$h" ]; then printf '\n%s:\n' "$h"; fi; done
        fi
    } > "$depfile"
    exit 0
else
    [ -n "$out" ] || { echo "msvc-cc-wrapper: link mode with no -o output" >&2; exit 1; }
    if [ "$building_dll" = "yes" ]; then
        # msvc-shared-lib-export-req: a DLL exports what its objects define
        # with no __declspec(dllexport) needed, as on every other toolchain
        # -- without exports link.exe writes no import library and nothing
        # can link the DLL. Generate a .def listing every external symbol
        # the objects define (CMake's WINDOWS_EXPORT_ALL_SYMBOLS does the
        # same), data symbols marked DATA; compiler-generated ones are left
        # out: reserved __ names, deleting destructors (??_G, ??_E), string
        # literals (??_C@), RTTI (??_R), throw info (_CT, _TI, _CTA).
        # @impl 0f87-6a9a-b51c-b267
        # A DLL linked straight from sources (`$CC -shared -o x.dll x.c`, as
        # a FETCH_BUILD_CMD may): compile them first, into a directory of
        # their own beside the DLL, so there are objects to export from.
        if [ "$own_def" = no ] && [ -n "$csources" ]; then
            objdir="${out%.*}.objs"
            mkdir -p "$objdir"
            tool_failed=yes
            eval "cl.exe /nologo /c $cflags $csources /Fo\"$(winpath "$objdir")\\\\\""
            tool_failed=""
            for o in "$objdir"/*.obj; do
                objects="$objects \"$(winpath "$o")\""
            done
            sources="$objects $libinputs"
        fi
        if [ "$own_def" = no ] && [ -n "$objects" ]; then
            # beside the objects, not in the DLL's lib/ (copy-up's input)
            def="$objdir/$(basename "${out%.*}").def"
            syms=$(eval "dumpbin.exe /nologo /symbols $objects") || {
                echo "msvc-cc-wrapper: cannot list the symbols of $out's objects for its export list (dumpbin.exe /symbols failed, above) -- the DLL would have no import library" >&2
                tool_failed=yes; exit 1
            }
            # symbols already exported by __declspec(dllexport) (an /EXPORT:
            # directive in the object) stay out: listed twice, link.exe
            # warns LNK4197
            dirs=$(eval "dumpbin.exe /nologo /directives $objects" | tr -d '\r' | tr ' ' '\n' | sed -n 's|^/EXPORT:\([^,]*\).*|\1|p') || dirs=""
            {
                echo "LIBRARY \"$(basename "$out")\""
                echo "EXPORTS"
                { printf '%s\n' "$dirs" | sed 's/^/DIRECTIVE /'; printf '%s\n' "$syms"; } | tr -d '\r' | awk '
                    $1 == "DIRECTIVE" { seen[$2] = 1; next }
                    / External / && $3 ~ /^SECT/ {
                        i = index($0, "| "); if (i == 0) next
                        n = substr($0, i + 2); sub(/ .*/, "", n)
                        if (n ~ /^(__|\?\?_[GECR]|_CT|_TI)/ || seen[n]++) next
                        print "    " n ($0 ~ / notype \(\) / ? "" : " DATA")
                    }'
            } > "$def"
            linkflags="$linkflags /DEF:\"$(winpath "$def")\""
        fi
        # /Fe: still names cl's own output for consistency/diagnostics;
        # the authoritative name for a DLL link is /OUT: after /link.
        tool_failed=yes
        eval "cl.exe /nologo $cflags $sources /link $linkflags /OUT:\"$(winpath "$out")\""
    else
        tool_failed=yes
        eval "cl.exe /nologo $cflags $sources /Fe:\"$(winpath "$out")\" /link $linkflags"
    fi
fi
