# mk.toolchain.msvc.mk — MSVC toolchain bundle (tier 1, win-target-tiered-toolchain-req)
#
# Native MSVC (cl.exe/link.exe/lib.exe), driven command-line-only via bmake
# exactly like every other platform in this project -- the difference is
# entirely absorbed by CC/CXX/AR pointing at wrapper scripts
# (scripts/msvc-cc-wrapper.sh, scripts/msvc-lib-wrapper.sh) that translate
# the gcc/clang-style flags mk.prog.mk/mk.lib.mk's recipes already emit
# (-c, -o, -I, -D, -L, -l, -shared, -Wl,--out-implib,...) into cl.exe/
# link.exe/lib.exe syntax, including Cygwin POSIX-to-Windows path
# translation via cygpath. mk.prog.mk/mk.lib.mk themselves stay unchanged
# for this: only their WIN-target output-naming branch (PROG.exe,
# LIB.dll+LIB.lib, LIB.lib for static) is toolchain-agnostic and shared
# with the Cygwin-native gcc/llvm tier.
#
# Precondition: this file only makes sense when running from a Cygwin
# host (TARGET=win via the host-detection in mk.common.mk). An explicit
# TARGET=win cross-invocation is NOT supported here -- MSVC cannot itself
# cross-compile from a non-Windows host; that's the mingw-w64 tier's job,
# in mk.toolchain.llvm.mk.
#
# cl.exe/link.exe/lib.exe do not need to already be on PATH: if a Visual
# Studio developer environment is already active (e.g. launched from an
# "x64 Native Tools Command Prompt", or vcvarsall.bat was run manually),
# that's used as-is and nothing further happens. Otherwise mk.vcvarsall.mk
# discovers the installed MSVC toolset + Windows SDK via vswhere.exe and
# builds the equivalent PATH/INCLUDE/LIB itself -- so a plain Cygwin shell
# with no prior setup works too.

.if !defined(_MK_TOOLCHAIN_MSVC_MK_)
_MK_TOOLCHAIN_MSVC_MK_ = 1

# clang-msvc-toolchain-req: also included by mk.toolchain.llvm.mk for
# TOOLCHAIN=llvm ABI=msvc, with _BMK_MSVC_DRIVER=clang -- the same MSVC
# headers and libraries, compiled by clang-cl (cl.exe's own syntax, so the
# wrapper is unchanged) and linked by lld-link.
# @impl 7854-6ae5-dc2f-8e71
_BMK_MSVC_DRIVER ?= cl
.if ${_BMK_MSVC_DRIVER} == "clang"
_BMK_MSVC_NAME = TOOLCHAIN=llvm ABI=msvc
.else
_BMK_MSVC_NAME = TOOLCHAIN=msvc
.endif

# `clean TARGET=all` compiles nothing: it only wipes every target's output,
# so it must not stop here (case 14 under TOOLCHAIN=msvc did).
.if ${BMK_IS_NATIVE_BUILD} == "no" && ${CLEAN_ALL_TARGETS} != "yes"
.  if ${_BMK_MSVC_DRIVER} == "clang"
.    error "TOOLCHAIN=llvm ABI=msvc builds only on a Windows (Cygwin) host for now: it needs the MSVC headers and libraries that Visual Studio or an EWDK provides there -- for win-target output from another host, use TOOLCHAIN=llvm without ABI= (mingw-w64 cross-compilation)."
.  else
.    error "TOOLCHAIN=msvc cannot cross-compile (MSVC only ever targets Windows, from Windows) -- for a non-Cygwin host producing win-target output, use TOOLCHAIN=llvm instead (mingw-w64 cross-compilation)."
.  endif
.endif

.if empty(.MAKEFLAGS:M-V*) && !make(clean) && (${_BMK_PASS_OK} != "yes" || !defined(BMK_MSVC_BIN) || !defined(_MSVC_VER))
_MSVC_CL != command -v cl 2>/dev/null || true
.  if empty(_MSVC_CL)
# @impl 0f87-6a9a-d311-f245
.    include "${BMK_MKDIR}/mk.vcvarsall.mk"
# Handed to the wrappers in the environment, so CC stays a plain command
# line (no quotes, no spaces inside words): anything may run it as $CC.
BMK_MSVC_BIN     := ${_MSVC_BIN}
BMK_MSVC_INCLUDE := ${_MSVC_INCLUDE}
BMK_MSVC_LIB     := ${_MSVC_LIB}
.    export BMK_MSVC_BIN BMK_MSVC_INCLUDE BMK_MSVC_LIB _MSVC_VER
.  else
_MSVC_LIB_TOOL != command -v lib 2>/dev/null || true
.    if empty(_MSVC_LIB_TOOL)
.      error "${_BMK_MSVC_NAME}: cl.exe was found on PATH but lib.exe was not -- PATH is only partially set up for MSVC. Launch from a full Visual Studio Developer environment, or unset PATH's partial override and let mk.vcvarsall.mk discover it instead."
.    endif
.  endif
.endif

# clang's tools, handed to the wrappers like the MSVC paths: BMK_MSVC_CL
# replaces cl.exe (linking through lld-link), BMK_MSVC_LIBEXE lib.exe.
# -fms-compatibility-version from the toolset found (14.MM is _MSC_VER
# 19MM): clang cannot tell it from INCLUDE alone and guessed 1933 for a
# 14.50 toolset (2026-10-30). /EHsc: clang-cl has C++ exceptions off by
# default and refuses throw and try (cl.exe compiles them, with a warning);
# first on the command line, so a module's own -fno-exceptions still wins.
.if ${_BMK_MSVC_DRIVER} == "clang" && empty(.MAKEFLAGS:M-V*) && !make(clean) && (${_BMK_PASS_OK} != "yes" || !defined(BMK_MSVC_CL) || !defined(BMK_MSVC_LIBEXE))
_MSVC_CLANG_CL != command -v clang-cl 2>/dev/null || true
_MSVC_LLD_LINK != command -v lld-link 2>/dev/null || true
.  if empty(_MSVC_CLANG_CL) || empty(_MSVC_LLD_LINK)
.    error "TOOLCHAIN=llvm ABI=msvc needs clang-cl and lld-link on PATH (${_MSVC_CLANG_CL:Uclang-cl not found} ${_MSVC_LLD_LINK:Ulld-link not found}) -- on Cygwin they come with the clang and lld packages."
.  endif
BMK_MSVC_CL := ${_MSVC_CLANG_CL} -fuse-ld=lld /EHsc${_MSVC_VER:D -fms-compatibility-version=19.${_MSVC_VER:C/^14\.([0-9]+).*/\1/}}
BMK_MSVC_LIBEXE := ${_MSVC_LLD_LINK} /lib
.  export BMK_MSVC_CL BMK_MSVC_LIBEXE
.endif

# @impl 0f87-6a98-96de-1865
CC  = sh ${BMK_MKDIR:Q}/../scripts/msvc-cc-wrapper.sh
CXX = sh ${BMK_MKDIR:Q}/../scripts/msvc-cc-wrapper.sh
LD  = ${CC}
AR  = sh ${BMK_MKDIR:Q}/../scripts/msvc-lib-wrapper.sh
AS  ?= as
RANLIB = true

.endif # _MK_TOOLCHAIN_MSVC_MK_
