# mk.requires.mk -- REQUIRES= prerequisite checking (requires-software-prereq-req,
# requires-header-form-req, requires-header-prefix-probe-req). Included by
# mk.prog.mk/mk.lib.mk right after the "pre" local-hook phase.

# ---------------------------------------------------------------------------
# REQUIRES= (requires-software-prereq-req): external prerequisite software
# this module needs already installed -- not fetched, imported, or staged
# by Bmake It (that's IMPORT=/fetch:/fetch-bin:/FETCH_BUILD=, a different
# thing: those acquire and stage a library, this checks and errors). Each
# name is checked via `pkg-config --exists`, falling back to `command -v`
# for a CLI-tool-style prerequisite pkg-config wouldn't know about (cmake,
# ogr2ogr, ...). A `header:<path>` entry (requires-header-form-req) is
# checked differently: it has no package name and no CLI tool, only a
# header -- e.g. a header-only library with no .pc file (glm on a
# distro that ships no compiled lib for it). Checked by preprocessing a
# trivial translation unit that #includes <path>, tried twice: first
# CC/CFLAGS in C mode (-x c), then, if that fails, CXX/CXXFLAGS in C++
# mode (-x c++) -- both as defined at this point (the module's own
# makefile, mk.common.mk's SANITIZE=/OPENMP= contributions, and any
# "pre" hook's CFLAGS/CXXFLAGS -- this file is included after the "pre"
# phase, but before the "local" post-hook phase). Two separate attempts
# are required, not one pass with both flag sets merged: a C++-only
# header's -I is commonly carried on CXXFLAGS alongside a real
# -std=c++.. flag, which clang/gcc reject outright when combined with
# -x c ("invalid argument '-std=c++17' not allowed with 'C'") -- found
# empirically while testing this fix. Unlike the dylib/library-file
# case, -E only preprocesses directives and never parses the template/
# namespace body, so neither attempt needs to actually understand the
# header's C-vs-C++ content, only find and open it. A missing one (of
# either form) is a parse-time .error naming the module and which
# entry couldn't be found -- fails immediately, before any real build
# work (including a slow FETCH_BUILD= configure) starts, matching this
# project's existing CC/CXX-resolution and IMPORT=pkg:-resolution
# failure style. No Find-module system, no version constraints, no per-
# platform install-command database -- "just check or error", not all
# that plumbing. Deliberately not cross-sysroot-aware: checks the HOST's
# own pkg-config/PATH/CC, same as IMPORT=pkg:'s own non-cross-aware
# fallback -- for a genuinely cross-compiled target this answers "is it
# present for a native build," not "is it present in the target's own
# sysroot".
#
# requires-header-prefix-probe-req: a header: entry that neither compiler
# attempt finds is ALSO accepted when it exists under <prefix>/include for
# any prefix IMPORT_LIB=none's step-4 probe uses (_TOOL_PREFIXES with the
# trailing bin/ stripped) -- found in real use: MacPorts' clang does not
# search /opt/local/include by default, so a header installed there (glm)
# was found by the import but rejected by REQUIRES=, and passing it would
# have needed exactly the -I hook IMPORT_LIB=none exists to remove. This
# is a presence check only: it does not add an -I, so a module that
# #includes the header directly (no IMPORT=) still needs its own. This
# file runs after the "pre" hook phase (not inside mk.common.mk), so a
# pre hook's CFLAGS+=-I or _TOOL_PREFIXES override is seen too.
# Skipped for `clean`/`help` and a `-V` query (same guard already used by
# mk.toolchain.llvm.mk/msvc.mk for their own parse-time resolution
# failures) -- a missing prerequisite must never block cleaning a module
# or asking for help.
# @impl 0f87-6aba-6ced-1a19
# @impl 0f87-6abe-49e1-15bc
# @impl 0f87-6abf-aeb9-6878
# ---------------------------------------------------------------------------
REQUIRES ?=
.if !empty(REQUIRES) && empty(.MAKEFLAGS:M-V*) && !make(clean) && !make(help)
.for _r in ${REQUIRES}
.  if ${_r:C/:.*//} == "header"
_REQUIRES_HDR.${_r} = ${_r:C/^[^:]*://}
_REQUIRES_FOUND.${_r} != (echo "\#include <${_REQUIRES_HDR.${_r}}>" | ${CC} ${CFLAGS} -x c -E -o /dev/null - >/dev/null 2>&1 && echo yes) || (echo "\#include <${_REQUIRES_HDR.${_r}}>" | ${CXX} ${CXXFLAGS} -x c++ -E -o /dev/null - >/dev/null 2>&1 && echo yes) || echo no
.    for _p in ${_TOOL_PREFIXES:H:O:u}
.      if ${_REQUIRES_FOUND.${_r}} != "yes" && exists(${_p}/include/${_REQUIRES_HDR.${_r}})
_REQUIRES_FOUND.${_r} = yes
.      endif
.    endfor
.    if ${_REQUIRES_FOUND.${_r}} != "yes"
.      error "REQUIRES=${_r}: header ${_REQUIRES_HDR.${_r}} not found -- tried ${CC}/${CXX} with the current CFLAGS/CXXFLAGS, and <prefix>/include for: ${_TOOL_PREFIXES:H:O:u} -- add its include directory to CFLAGS or CXXFLAGS or install the providing package (see README.md Prerequisites) before building"
.    endif
.  else
_REQUIRES_FOUND.${_r} != (command -v pkg-config >/dev/null 2>&1 && pkg-config --exists ${_r} 2>/dev/null && echo yes) || (command -v ${_r} >/dev/null 2>&1 && echo yes) || echo no
.    if ${_REQUIRES_FOUND.${_r}} != "yes"
.      error "REQUIRES=${_r}: not found via pkg-config or on PATH -- install it via your host's package manager (see README.md Prerequisites) before building"
.    endif
.  endif
.endfor
.endif
