# mk.toolchain.gcc.mk — GNU gcc toolchain bundle
# REQ-toolchain-mk-must-set-explicit-cc-paths-req-v5: search PATH, then a
# list of common install prefixes -- never a single hardcoded absolute path.
# See mk.toolchain.llvm.mk for why (silently substituting a different
# compiler is a real failure mode found on real NetBSD/pkgsrc).

.if !defined(_MK_TOOLCHAIN_GCC_MK_)
_MK_TOOLCHAIN_GCC_MK_ = 1

.if empty(.MAKEOVERRIDES:MCC)
_GCC_CC != command -v gcc 2>/dev/null || \
    for _p in ${_TOOL_PREFIXES}; do \
        [ -x "$$_p/gcc" ] && { echo "$$_p/gcc"; break; }; \
    done
.  if !empty(_GCC_CC)
CC  = ${_GCC_CC}
CXX = ${_GCC_CC:S/gcc$/g++/}
.  else
.    error "TOOLCHAIN=gcc: no gcc found on PATH or this OS's known install prefixes (${_TOOL_PREFIXES}). Add gcc to PATH, set TOOLCHAIN=llvm, or set CC=/path/to/gcc explicitly."
.  endif
.endif

LD  ?= ${CC}
AR  ?= ar
AS  ?= as
RANLIB ?= ranlib

.endif # _MK_TOOLCHAIN_GCC_MK_
