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

.if empty(.MAKEOVERRIDES:MCC)
_GCC_CC != _found=""; \
    for _p in ${_TOOL_PREFIXES}; do \
        if [ -x "$$_p/gcc" ]; then _found="$$_p/gcc"; break; fi; \
    done; \
    if [ -n "$$_found" ]; then echo "$$_found"; else command -v gcc 2>/dev/null || true; fi
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
