# mk.toolchain.gcc.mk — GNU gcc toolchain bundle
# REQ-toolchain-mk-must-set-explicit-cc-paths-req-v5: search PATH, then a
# list of common install prefixes -- never a single hardcoded absolute path.
# See mk.toolchain.llvm.mk for why (silently substituting a different
# compiler is a real failure mode found on real NetBSD/pkgsrc).
#
# @impl 0f87-6aa9-39c9-34a5 -- _TOOL_PREFIXES checked before ambient $PATH,
# same reasoning as mk.toolchain.llvm.mk.

.if !defined(_MK_TOOLCHAIN_GCC_MK_)
_MK_TOOLCHAIN_GCC_MK_ = 1

# mingw-on-cygwin-req: mingw-w64 output (ABI=mingw on a Cygwin host, or a
# cross build to win) needs gcc's mingw-w64 build, a separate compiler
# named after its triple, with its own binutils -- plain gcc on a Cygwin
# host makes Cygwin (cygwin1.dll) output.
# @impl 7854-6ad0-e970-479a
.if ${_BMK_WIN_MINGW:Uno} == "yes"
.  if empty(.MAKEOVERRIDES:MCC)
_GCC_MINGW_CC != command -v ${_MINGW_TRIPLE}-gcc 2>/dev/null || true
.    if empty(_GCC_MINGW_CC)
.      error "TOOLCHAIN=gcc for mingw-w64 output (TARGET=win-${TARGET_ARCH}${ABI:D, ABI=${ABI}}) needs ${_MINGW_TRIPLE}-gcc on PATH, and it is not there. On Cygwin: mingw64-x86_64-gcc-core (C) and mingw64-x86_64-gcc-g++ (C++), which exist for x86_64 only. On Debian/Ubuntu: the mingw-w64 package (x86_64/i686). For aarch64, no gcc package is common: use TOOLCHAIN=llvm with an llvm-mingw release as BMK_MINGW_SYSROOT. Without ABI=mingw, a Cygwin host's own gcc builds Cygwin output instead."
.    endif
CC  = ${_GCC_MINGW_CC}
CXX = ${_GCC_MINGW_CC:S/gcc$/g++/}
.  endif
_GCC_MINGW_AR != command -v ${_MINGW_TRIPLE}-ar 2>/dev/null || true
.  if !empty(_GCC_MINGW_AR)
AR     = ${_GCC_MINGW_AR}
RANLIB = ${_GCC_MINGW_AR:S/-ar$/-ranlib/}
.  endif
.elif empty(.MAKEOVERRIDES:MCC)
_GCC_CC != _found=""; \
    for _p in ${_TOOL_PREFIXES}; do \
        if [ -x "$$_p/gcc" ]; then _found="$$_p/gcc"; break; fi; \
    done; \
    if [ -n "$$_found" ]; then echo "$$_found"; else command -v gcc 2>/dev/null || true; fi
.  if !empty(_GCC_CC)
CC  = ${_GCC_CC}
CXX = ${_GCC_CC:S/gcc$/g++/}
# @impl 0f87-6ad7-1f32-4d7a
# A ports/pkgsrc gcc on a BSD keeps its runtime (libgcc_s, libstdc++) outside
# the system library path and records no rpath to it: a C++ binary then loads
# the base system's older libgcc_s and will not start (FreeBSD 15.1 with
# gcc14: "version GCC_4.5.0 required by libstdc++.so.6 not found").
.    if ${_HOST_OS} == "freebsd" || ${_HOST_OS} == "netbsd" || ${_HOST_OS} == "openbsd" || ${_HOST_OS} == "dragonfly"
_GCC_RT_DIR != _f=$$(${_GCC_CC} -print-file-name=libgcc_s.so 2>/dev/null); \
    case "$$_f" in /usr/lib/*|/lib/*) ;; /*) dirname "$$_f" ;; esac
.      if !empty(_GCC_RT_DIR)
LDFLAGS += -Wl,-rpath,${_GCC_RT_DIR}
.      endif
.    endif
.  else
.    error "TOOLCHAIN=gcc: no gcc found on PATH or this OS's known install prefixes (${_TOOL_PREFIXES}). Add gcc to PATH, set TOOLCHAIN=llvm, or set CC=/path/to/gcc explicitly."
.  endif
.endif

LD  ?= ${CC}
AR  ?= ar
AS  ?= as
RANLIB ?= ranlib

.endif # _MK_TOOLCHAIN_GCC_MK_
