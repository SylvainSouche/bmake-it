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

.if ${BMK_IS_NATIVE_BUILD} == "no"
.  error "TOOLCHAIN=msvc cannot cross-compile (MSVC only ever targets Windows, from Windows) -- for a non-Cygwin host producing win-target output, use TOOLCHAIN=llvm instead (mingw-w64 cross-compilation)."
.endif

.if empty(.MAKEFLAGS:M-V*) && !make(clean)
_MSVC_CL != command -v cl 2>/dev/null || true
.  if empty(_MSVC_CL)
# @impl 0f87-6a9a-d311-f245
.    include "${BMK_MKDIR}/mk.vcvarsall.mk"
_MSVC_ENV_PREFIX = env PATH="${_MSVC_BIN}:$$PATH" INCLUDE="${_MSVC_INCLUDE}" LIB="${_MSVC_LIB}"
.  else
_MSVC_LIB_TOOL != command -v lib 2>/dev/null || true
.    if empty(_MSVC_LIB_TOOL)
.      error "TOOLCHAIN=msvc: cl.exe was found on PATH but lib.exe was not -- PATH is only partially set up for MSVC. Launch from a full Visual Studio Developer environment, or unset PATH's partial override and let mk.vcvarsall.mk discover it instead."
.    endif
_MSVC_ENV_PREFIX =
.  endif
.endif

# @impl 0f87-6a98-96de-1865
CC  = ${_MSVC_ENV_PREFIX} sh ${BMK_MKDIR}/../scripts/msvc-cc-wrapper.sh
CXX = ${_MSVC_ENV_PREFIX} sh ${BMK_MKDIR}/../scripts/msvc-cc-wrapper.sh
LD  = ${CC}
AR  = ${_MSVC_ENV_PREFIX} sh ${BMK_MKDIR}/../scripts/msvc-lib-wrapper.sh
AS  ?= as
RANLIB = true

.endif # _MK_TOOLCHAIN_MSVC_MK_
