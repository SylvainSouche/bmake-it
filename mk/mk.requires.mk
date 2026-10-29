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
# requires-preflight-req: BMK_REQUIRES_CHECK=yes (the workspace's and
# framework's preflight, a -V query of _REQUIRES_REPORT) runs the same
# checks without stopping: each missing entry goes into _REQUIRES_MISSING,
# with how it was looked for (_REQUIRES_HOW.<entry>: header=<prefixes tried>, pkg, path or
# sysroot=<dir>), so ONE list of everything missing is printed before
# anything is built. A plain module build still stops on the first.
# @impl 7854-6ae3-0b4f-513f
_REQUIRES_MISSING =
.if !empty(REQUIRES) && (empty(.MAKEFLAGS:M-V*) || ${BMK_REQUIRES_CHECK:U} == "yes") && !make(clean) && !make(help)
# Is the pkg-config to ask there at all? Without it every library looked
# missing and the message still said "not found via pkg-config" -- with curl
# and tiff installed (FreeBSD, no pkgconf, 2026-10-29). Say which it is.
.  if !empty(_BMK_PKG_CONFIG)
_REQUIRES_PKGCONF_OK != command -v ${_BMK_PKG_CONFIG} >/dev/null 2>&1 && echo yes || echo no
.  endif
.for _r in ${REQUIRES}
.  if ${_r:C/:.*//} == "header"
_REQUIRES_HDR.${_r} = ${_r:C/^[^:]*://}
_REQUIRES_FOUND.${_r} != (echo "\#include <${_REQUIRES_HDR.${_r}}>" | ${CC} ${CFLAGS} -x c -E -o /dev/null - >/dev/null 2>&1 && echo yes) || (echo "\#include <${_REQUIRES_HDR.${_r}}>" | ${CXX} ${CXXFLAGS} -x c++ -E -o /dev/null - >/dev/null 2>&1 && echo yes) || echo no
.    for _p in ${_TOOL_PREFIXES:H:O:u}
.      if ${_REQUIRES_FOUND.${_r}} != "yes" && exists(${_p}/include/${_REQUIRES_HDR.${_r}})
_REQUIRES_FOUND.${_r} = yes
.      endif
.    endfor
.    if ${_REQUIRES_FOUND.${_r}} != "yes" && ${BMK_REQUIRES_CHECK:U} == "yes"
_REQUIRES_MISSING += ${_r}
_REQUIRES_HOW.${_r} = header=${_TOOL_PREFIXES:H:O:u:ts,}
.    elif ${_REQUIRES_FOUND.${_r}} != "yes"
.      error "REQUIRES=${_r}: header ${_REQUIRES_HDR.${_r}} not found -- tried ${CC}/${CXX} with the current CFLAGS/CXXFLAGS, and <prefix>/include for: ${_TOOL_PREFIXES:H:O:u} -- add its include directory to CFLAGS or CXXFLAGS or install the providing package (see README.md Prerequisites) before building"
.    endif
.  else
# pkg-config-matches-output-abi-req: the pkg-config describing the output
# being built (mk.common.mk), not always the host's -- for ABI=mingw on
# Cygwin, plain pkg-config would find Cygwin's libcurl and pass.
# @impl 7854-6ad1-10ad-4843
.    if empty(_BMK_PKG_CONFIG)
_REQUIRES_FOUND.${_r} != command -v ${_r} >/dev/null 2>&1 && echo yes || echo no
.    else
_REQUIRES_FOUND.${_r} != (command -v ${_BMK_PKG_CONFIG} >/dev/null 2>&1 && env ${_BMK_PKG_CONFIG_ENV} ${_BMK_PKG_CONFIG} --exists ${_r} 2>/dev/null && echo yes) || (command -v ${_r} >/dev/null 2>&1 && echo yes) || echo no
.    endif
.    if ${_REQUIRES_FOUND.${_r}} != "yes" && ${BMK_REQUIRES_CHECK:U} == "yes"
_REQUIRES_MISSING += ${_r}
.      if empty(_BMK_PKG_CONFIG)
_REQUIRES_HOW.${_r} = path
.      elif ${_REQUIRES_PKGCONF_OK} == "no"
_REQUIRES_HOW.${_r} = nopkgconfig=${_BMK_PKG_CONFIG}
.      elif ${BMK_IS_NATIVE_BUILD} == "no" && !empty(_BMK_PKG_CONFIG_SYSROOT)
_REQUIRES_HOW.${_r} = sysroot=${_BMK_PKG_CONFIG_SYSROOT}
.      else
_REQUIRES_HOW.${_r} = pkg
.      endif
.    elif ${_REQUIRES_FOUND.${_r}} != "yes"
.      if empty(_BMK_PKG_CONFIG)
.        error "REQUIRES=${_r}: not found on PATH, and not checked with pkg-config -- ${_BMK_PKG_CONFIG_MISSING}"
.      elif ${_REQUIRES_PKGCONF_OK} == "no"
.        error "REQUIRES=${_r}: could not be checked -- ${_BMK_PKG_CONFIG} is not installed (the package is usually named pkgconf or pkg-config), and ${_r} is not a program on PATH either; install pkg-config, then build again"
.      else
# (plain comments here: `.  # ...` is "Unknown directive" to a newer bmake,
# FreeBSD 15's -- 2026-10-29)
# @impl 0f87-6ad7-1f32-4d7a
.        if empty(_BMK_PKG_CONFIG_ENV)
_REQUIRES_VIA = ${_BMK_PKG_CONFIG}
.        else
_REQUIRES_VIA = ${_BMK_PKG_CONFIG} (with ${_BMK_PKG_CONFIG_ENV})
.        endif
# @impl 0f87-6adc-d727-1a3b
.        if ${BMK_IS_NATIVE_BUILD} == "no" && !empty(_BMK_PKG_CONFIG_SYSROOT)
.          error "REQUIRES=${_r}: not found via ${_REQUIRES_VIA} (the target's sysroot ${_BMK_PKG_CONFIG_SYSROOT}) nor as a program on PATH -- a library the ${TARGET}-${TARGET_ARCH} program links goes in that sysroot (one made from a ${TARGET}-${TARGET_ARCH} system with the package installed); a tool the build runs, such as cmake or flex, is installed on this host"
.        else
.          error "REQUIRES=${_r}: not found via ${_REQUIRES_VIA} or on PATH -- install it via your host's package manager (see README.md Prerequisites) before building"
.        endif
.      endif
.    endif
.  endif
.endfor
.endif
# The tools a module needs without naming them (preflight only; the build
# itself checks each where it uses it): a downloader for a fetch: archive not
# downloaded yet, unzip for a .zip, patch for FETCH_PATCHES=, cmake / meson
# and ninja for FETCH_BUILD=, yacc / lex for .y / .l sources.
.if ${BMK_REQUIRES_CHECK:U} == "yes" && !make(clean) && !make(help)
_REQ_TOOLS =
.  if !empty(IMPORT:U:Mfetch*)
# (a file:// URL is copied, no downloader: case 98)
.    if !empty(FETCH_URL:U) && empty(FETCH_URL:U:[1]:Mfile\://*) && !exists(${.CURDIR}/distfiles/${FETCH_URL:[1]:T})
_REQ_DL != for t in curl wget fetch ftp; do command -v $$t >/dev/null 2>&1 && { echo yes; exit; }; done; echo no
.      if ${_REQ_DL} == "no"
_REQUIRES_MISSING += downloader
_REQUIRES_HOW.downloader = path=curl,wget,fetch,ftp
.      endif
.    endif
# (conditionals, not :C/.*/x/ -- that turns an empty value into x)
.    if !empty(FETCH_URL:U:M*.zip)
_REQ_TOOLS += unzip
.    endif
.    if !empty(FETCH_PATCHES:U)
_REQ_TOOLS += patch
.    endif
.    if ${FETCH_BUILD:U} == "cmake"
_REQ_TOOLS += cmake
.    elif ${FETCH_BUILD:U} == "meson"
_REQ_TOOLS += meson ninja
.    endif
.  endif
_REQ_GRAMMAR != find ${.CURDIR}/src \( -name '*.y' -o -name '*.yy' \) 2>/dev/null | head -1
_REQ_LEXER   != find ${.CURDIR}/src \( -name '*.l' -o -name '*.ll' \) 2>/dev/null | head -1
.  if !empty(_REQ_GRAMMAR)
_REQ_TOOLS += ${YACC:Uyacc:[1]}
.  endif
.  if !empty(_REQ_LEXER)
_REQ_TOOLS += ${LEX:Ulex:[1]}
.  endif
.  for _t in ${_REQ_TOOLS:O:u}
_REQ_HAVE.${_t} != command -v ${_t:[1]} >/dev/null 2>&1 && echo yes || echo no
.    if ${_REQ_HAVE.${_t}} == "no"
_REQUIRES_MISSING += ${_t}
_REQUIRES_HOW.${_t} = tool
.    endif
.  endfor
.endif

# one word per missing entry, <entry>%<how>, for the preflight to print
_REQUIRES_REPORT = ${_REQUIRES_MISSING:@r@${r}%${_REQUIRES_HOW.${r}}@} ${_TST_ATF_REPORT:U}
