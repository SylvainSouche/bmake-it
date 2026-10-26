# testlib.sh -- sourced by test cases (`. "$BMK_TESTLIB"`), never run.
# run-tests.sh exports BMK_TESTLIB as this file's absolute path.
#
# The artifact names and the library search variable a built program
# needs differ per target; a case must not hardcode the Unix ones (`app`,
# `libx.a`, `libx.so.3`, LD_LIBRARY_PATH) or it fails on a target that does
# not use them -- on Windows (Cygwin, mingw, MSVC output) 37 cases did, all
# for that reason alone (2026-10-26). The suite builds natively, so the
# target is the host: uname -s decides.
# @impl 7854-6adf-8c28-260c (harness-cases-target-neutral-req)

case "$(uname -s)" in
    CYGWIN*|MINGW*|MSYS*) BMK_T_OS=win ;;
    Darwin)               BMK_T_OS=macos ;;
    *)                    BMK_T_OS=elf ;;
esac

# prog_name <name>: the file name of program <name> (PROG=<name>).
prog_name() {
    case $BMK_T_OS in win) echo "$1.exe" ;; *) echo "$1" ;; esac
}

# find_prog <dir> <name> [find predicates...]: the first built program
# <name> under <dir> (a regular file), empty if none.
find_prog() {
    _d=$1; _n=$(prog_name "$2"); shift 2
    find "$_d" -type f -name "$_n" "$@" | head -1
}

# static_lib <name>: the static library file for LIB=<name>, LIB_SHARED=NO.
static_lib() {
    case $BMK_T_OS in win) echo "$1.lib" ;; *) echo "lib$1.a" ;; esac
}

# shared_lib <name> [major]: the shared library file for LIB=<name>; with a
# major version, the versioned name where the platform has one (Windows
# shared libraries carry their version inside, never in the file name).
shared_lib() {
    case $BMK_T_OS in
        win)   echo "$1.dll" ;;
        macos) echo "lib$1${2:+.$2}.dylib" ;;
        *)     echo "lib$1.so${2:+.$2}" ;;
    esac
}

# libpath_var: the variable the dynamic loader searches for shared libraries.
libpath_var() {
    case $BMK_T_OS in win) echo PATH ;; macos) echo DYLD_LIBRARY_PATH ;; *) echo LD_LIBRARY_PATH ;; esac
}

# with_libdir <dirs> <cmd> [args...]: run <cmd> with <dirs> (colon list)
# prepended to the loader's search variable.
with_libdir() {
    _v=$(libpath_var); _dirs=$1; shift
    eval "_old=\${$_v:-}"
    env "$_v=$_dirs${_old:+:$_old}" "$@"
}

# prog_libdir <path-to-built-program>: the lib/ beside its bin/ -- where
# copy-up put the shared libraries it links. ELF and macOS programs find
# them through an rpath; a Windows program has none and needs this on PATH.
prog_libdir() {
    echo "$(dirname "$(dirname "$1")")/lib"
}

# shlib_flags <dir> <name>: compiler flags that link a shared library for
# -l<name> into <dir>, named as that platform's linker looks for it -- on
# Windows a DLL plus its import library lib<name>.dll.a (ld and lld do not
# look for lib<name>.so there).
shlib_flags() {
    case $BMK_T_OS in
        win)   echo "-shared -o $1/lib$2.dll -Wl,--out-implib,$1/lib$2.dll.a" ;;
        macos) echo "-dynamiclib -o $1/lib$2.dylib" ;;
        *)     echo "-shared -fPIC -o $1/lib$2.so" ;;
    esac
}

# make_shared_lib <dir> <name> <compiler args...>: build that library with $CC.
make_shared_lib() {
    _dir=$1; _name=$2; shift 2
    # shellcheck disable=SC2046
    ${CC:-cc} $(shlib_flags "$_dir" "$_name") "$@"
}

# need_tool <tool> [why]: skip the case (exit 77, the harness's SKIP) when a
# tool it needs is not installed (harness-tool-presence-check-or-install-req).
need_tool() {
    command -v "$1" >/dev/null 2>&1 || { echo "skip: $1 not installed${2:+ -- $2}" >&2; exit 77; }
}
