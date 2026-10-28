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

# harness-windows-runtime-programs-req (CC default, run_prog, with_libdir's
# \r stripping and path normalisation, below)
# @impl 7854-6adf-d52e-740f
# The compiler a case builds its fake libraries with must produce objects
# for the runtime under test: under ABI=mingw a Cygwin-built DLL cannot be
# loaded by a mingw program. Cases use "$CC" (CC=${CC:-cc}); default it.
if [ -z "${CC:-}" ]; then
    case "${ABI:-}" in mingw) CC=x86_64-w64-mingw32-gcc ;; esac
fi
# Under TOOLCHAIN=msvc the fake libraries are built with Bmake It's own
# cl.exe/lib.exe wrappers, environment included (mk.vcvarsall.mk finds the
# toolset): asked from bmake itself, its CC and AR become two scripts.
if [ "${TOOLCHAIN:-}" = msvc ]; then
    _tl_d=$(mktemp -d "${TMPDIR:-/tmp}/bmk-tc.XXXXXX")
    cat > "$_tl_d/makefile" <<'EOF'
.include <mk.common.mk>
bmk-tc:
	@echo "$${BMK_MSVC_BIN:-}"
	@echo "$${BMK_MSVC_INCLUDE:-}"
	@echo "$${BMK_MSVC_LIB:-}"
	@echo ${CC:Q}
	@echo ${AR:Q}
EOF
    if ! _tl_tc=$(cd "$_tl_d" && bmake bmk-tc) || [ -z "$_tl_tc" ]; then
        echo "testlib: cannot get the MSVC compiler and archiver from bmake (TOOLCHAIN=msvc, above)" >&2
        exit 1
    fi
    _tl_l() { printf '%s\n' "$_tl_tc" | sed -n "$1p"; }
    BMK_MSVC_BIN=$(_tl_l 1) BMK_MSVC_INCLUDE=$(_tl_l 2) BMK_MSVC_LIB=$(_tl_l 3)
    export BMK_MSVC_BIN BMK_MSVC_INCLUDE BMK_MSVC_LIB
    printf '#!/bin/sh\nexec %s "$@"\n' "$(_tl_l 4)" > "$_tl_d/cc"
    printf '#!/bin/sh\nexec %s "$@"\n' "$(_tl_l 5)" > "$_tl_d/ar"
    chmod +x "$_tl_d/cc" "$_tl_d/ar"
    CC="$_tl_d/cc"; BMK_T_AR="$_tl_d/ar"
fi

# fake_ar <dir>/lib<name>.a <objects...>: archive a case's fake static
# library as the linker under test looks for -l<name>: lib<name>.a, or
# <name>.lib made by lib.exe under TOOLCHAIN=msvc.
fake_ar() {
    _fa=$1; shift
    if [ "${TOOLCHAIN:-}" = msvc ]; then
        _fb=$(basename "$_fa" .a)
        "$BMK_T_AR" rcs "$(dirname "$_fa")/${_fb#lib}.lib" "$@"
    else
        ar rcs "$_fa" "$@"
    fi
}

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
    # A Windows-runtime program (mingw, MSVC) writes \r\n: strip the \r so a
    # case can compare its output exactly. The program's exit status is kept.
    _wl_out=$(mktemp "${TMPDIR:-/tmp}/bmk-wl.XXXXXX")
    _wl_rc=0
    env "$_v=$_dirs${_old:+:$_old}" "$@" >"$_wl_out" || _wl_rc=$?
    tr -d '\r' <"$_wl_out"; rm -f "$_wl_out"
    return $_wl_rc
}

# run_prog <cmd> [args...]: run a built program (or `bmake run ...`), with
# the \r a Windows-runtime program writes stripped; exit status kept.
#   A native Windows program (mingw, MSVC) also sees PATH in Windows form --
#   Cygwin converts it for them -- and prints NAME=C:\...;C:\...: such a
#   value is turned back into the POSIX form the case compares with.
run_prog() {
    _rp_out=$(mktemp "${TMPDIR:-/tmp}/bmk-rp.XXXXXX")
    _rp_rc=0
    "$@" >"$_rp_out" 2>&1 || _rp_rc=$?
    if [ "$BMK_T_OS" = win ] && command -v cygpath >/dev/null 2>&1; then
        tr -d '\r' <"$_rp_out" | while IFS= read -r _rp_l; do
            case "$_rp_l" in
                [A-Za-z_]*=[A-Za-z]:\\*) printf '%s=%s\n' "${_rp_l%%=*}" "$(cygpath -u -p "${_rp_l#*=}")" ;;
                *) printf '%s\n' "$_rp_l" ;;
            esac
        done
    else
        tr -d '\r' <"$_rp_out"
    fi
    rm -f "$_rp_out"
    return $_rp_rc
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
    # MSVC: link.exe looks for -l<name> as <name>.lib
    [ "${TOOLCHAIN:-}" = msvc ] && { echo "-shared -o $1/$2.dll -Wl,--out-implib,$1/$2.lib"; return; }
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

# atf_pc <pkg-config args...>: pkg-config for ATF the way Bmake It looks it
# up (mk.atf.mk): also in the prefix of the kyua on PATH -- a source build in
# /usr/local is not on Cygwin's default pkg-config path.
atf_pc() {
    _k=$(command -v kyua 2>/dev/null || true)
    if [ -n "$_k" ]; then
        PKG_CONFIG_PATH="$(dirname "$(dirname "$_k")")/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}" pkg-config "$@"
    else
        pkg-config "$@"
    fi
}

# native_win_runtime: true when the output is for a native Windows runtime
# (ABI=mingw, TOOLCHAIN=msvc), where `bmake test` stops with an explanation:
# the ATF Kyua runs with on Windows is a Cygwin library.
native_win_runtime() {
    [ "$BMK_T_OS" = win ] && { [ "${TOOLCHAIN:-}" = msvc ] || [ "${ABI:-}" = mingw ]; }
}

# need_tool <tool> [why]: skip the case (exit 77, the harness's SKIP) when a
# tool it needs is not installed (harness-tool-presence-check-or-install-req).
need_tool() {
    command -v "$1" >/dev/null 2>&1 || { echo "skip: $1 not installed${2:+ -- $2}" >&2; exit 77; }
}
