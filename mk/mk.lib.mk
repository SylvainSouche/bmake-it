# mk.lib.mk — library module role
.if !defined(_MK_LIB_MK_)
_MK_LIB_MK_ = 1

.if !defined(BMK_MKDIR)
.  if exists(${.PARSEDIR}/mk.common.mk)
BMK_MKDIR := ${.PARSEDIR}
.  else
BMK_MKDIR = ${.CURDIR}
.  endif
.endif

.include "${BMK_MKDIR}/mk.common.mk"

# ---------------------------------------------------------------------------
# Local customization hooks (local-mk-hook-files-and-cascade-order-req)
# Module level sees PARENT_WS's mk/ (outermost), workspace's, framework's,
# then its own -- outer to inner, all included, in that order.
# ---------------------------------------------------------------------------
_LOCAL_MK_DIRS =
.for _p in ${PARENT_WS}
_LOCAL_MK_DIRS += ${_p}/mk
.endfor
_LOCAL_MK_DIRS += ${.CURDIR}/../../mk ${.CURDIR}/../mk ${.CURDIR}/mk

_LOCAL_MK_PHASE = pre
.include "${BMK_MKDIR}/mk.local.mk"

# @impl 0f87-6a98-5ff4-1b42
.if !defined(LIB) || empty(LIB)
_libdir != basename ${.CURDIR} .m
# Strip leading lib from directory name (libgreet.m → greet) for conventional -lgreet
LIB != echo ${_libdir} | sed 's/^lib//'
.endif

# @impl 0f87-6a9a-b8d2-c192
# <LIB>_BUILDING (uppercased), for the bmk_export.h BMK_DLLEXPORT/
# BMK_DLLIMPORT pattern (REQ-msvc-shared-lib-export-req): only ever
# defined while compiling THIS module's own sources, never for a
# consumer including the same public header elsewhere, so the header's
# own #if resolves to export here and import there.
CFLAGS   += -D${LIB:tu}_BUILDING
CXXFLAGS += -D${LIB:tu}_BUILDING

# @impl 0f87-6a98-77f0-ca62
.if !defined(LIB_SHARED)
LIB_SHARED = YES
.endif

.if ${LIB_SHARED} == "YES" && (!defined(SHLIB_MAJOR) || empty(SHLIB_MAJOR))
SHLIB_MAJOR = 1
.endif

# fetch-import-source-req: SRCS is REQUIRED, not auto-discovered, for
# IMPORT=fetch: -- paths relative to the resolved work tree, not src/.
# Auto-discovering an arbitrary upstream source tree would just as
# easily pull in its own tests/examples/tools.
.if ${IMPORT:Uno:C/:.*//} == "fetch"
.  if !defined(SRCS) || empty(SRCS)
.    error "IMPORT=${IMPORT}: SRCS= is required (paths relative to the fetched work tree) -- it is not auto-discovered for a fetched source, unlike an ordinary module's src/"
.  endif
.elif !defined(SRCS) || empty(SRCS)
SRCS != find src -type f \( -name '*.c' -o -name '*.cc' -o -name '*.cpp' -o -name '*.cxx' -o -name '*.y' -o -name '*.l' \) 2>/dev/null | sed 's|^src/||' || true
.endif

# Link driver selection (cxx-link-driver-selection-req): ${CXX} when SRCS
# contains a C++ source or LINK_CXX=yes overrides it explicitly (e.g. a
# C-sources-only module linking a static C++ library), ${CC} otherwise.
# @impl 0f87-6ab5-7f76-0dcf
_HAS_CXX_SRCS = no
.for _e in ${_CXX_EXTS}
.  if !empty(SRCS:M*.${_e})
_HAS_CXX_SRCS = yes
.  endif
.endfor
.if (defined(LINK_CXX) && ${LINK_CXX} == "yes") || ${_HAS_CXX_SRCS} == "yes"
_CCLINK = ${CXX}
.else
_CCLINK = ${CC}
.endif

.if exists(${.CURDIR}/include)
CFLAGS   += -I${.CURDIR}/include
CXXFLAGS += -I${.CURDIR}/include
.endif

_FWDIR = ${.CURDIR}/..
.if exists(${_FWDIR}/local/include)
CFLAGS   += -I${_FWDIR}/local/include
CXXFLAGS += -I${_FWDIR}/local/include
.endif
.if exists(${_FWDIR}/include)
CFLAGS   += -I${_FWDIR}/include
CXXFLAGS += -I${_FWDIR}/include
.endif
.if exists(${_FWDIR}/${BUILD_ROOT}/include)
CFLAGS   += -I${_FWDIR}/${BUILD_ROOT}/include
CXXFLAGS += -I${_FWDIR}/${BUILD_ROOT}/include
.endif

.if exists(${_FWDIR}/makefile)
_PREREQS != bmake -f ${_FWDIR}/makefile -V PREREQS 2>/dev/null || true
.  for _p in ${_PREREQS}
# REQ-headers-resolved-from-source-req: a PREREQS framework is resolved
# first within the current workspace, then falling back through PARENT_WS
# workspaces in declared order if not found locally.
# @impl 0f87-6a98-5e47-0c71
.    if exists(${_FWDIR}/../${_p})
_PREREQ_BASE.${_p} = ${_FWDIR}/..
.    else
.      for _pws in ${PARENT_WS}
.        if !defined(_PREREQ_BASE.${_p}) && exists(${_pws}/${_p})
_PREREQ_BASE.${_p} = ${_pws}
.        endif
.      endfor
.    endif
.    if defined(_PREREQ_BASE.${_p})
# public-headers-system-req (D3): see mk.prog.mk's identical comment.
.      if exists(${_PREREQ_BASE.${_p}}/${_p}/makefile)
_PREREQ_SYS.${_p} != bmake -f ${_PREREQ_BASE.${_p}}/${_p}/makefile -V PUBLIC_HEADERS_SYSTEM 2>/dev/null || true
.      endif
.      if ${_PREREQ_SYS.${_p}:Uno} == "yes"
_INCFLAG.${_p} = -isystem
.      else
_INCFLAG.${_p} = -I
.      endif
.      if exists(${_PREREQ_BASE.${_p}}/${_p}/include)
CFLAGS   += ${_INCFLAG.${_p}}${_PREREQ_BASE.${_p}}/${_p}/include
CXXFLAGS += ${_INCFLAG.${_p}}${_PREREQ_BASE.${_p}}/${_p}/include
.      endif
.      if exists(${_PREREQ_BASE.${_p}}/${_p}/${BUILD_ROOT}/include)
CFLAGS   += ${_INCFLAG.${_p}}${_PREREQ_BASE.${_p}}/${_p}/${BUILD_ROOT}/include
CXXFLAGS += ${_INCFLAG.${_p}}${_PREREQ_BASE.${_p}}/${_p}/${BUILD_ROOT}/include
.      endif
.      if exists(${_PREREQ_BASE.${_p}}/${_p}/${BUILD_ROOT}/lib)
LDFLAGS  += -L${_PREREQ_BASE.${_p}}/${_p}/${BUILD_ROOT}/lib
.      endif
.    endif
.  endfor
.endif

# Always add framework lib path (created by earlier modules during ordered build)
LDFLAGS += -L${_FWDIR}/${BUILD_ROOT}/lib
_LIB_SEARCH_DIRS = ${_FWDIR}/${BUILD_ROOT}/lib
.for _p in ${_PREREQS}
.  if defined(_PREREQ_BASE.${_p}) && exists(${_PREREQ_BASE.${_p}}/${_p}/${BUILD_ROOT}/lib)
_LIB_SEARCH_DIRS += ${_PREREQ_BASE.${_p}}/${_p}/${BUILD_ROOT}/lib
.  endif
.endfor

# Runtime search path for LIBS= dependencies -- without this, a shared lib
# built here that itself links another shared lib can't be *loaded* later
# (link-time -L/-l success doesn't imply dyld/ld.so can find it at run
# time). @rpath install names (macOS) and bare sonames (ELF) both need a
# consumer-side -rpath to resolve outside a system lib directory. No
# rpath concept on Windows -- DLL search order is PATH/same-dir based.
# @impl 0f87-6aa9-448d-537c
.if ${TARGET} != "win"
.  for _d in ${_LIB_SEARCH_DIRS}
LDFLAGS += -Wl,-rpath,${_d}
.  endfor
.endif

# @impl 0f87-6a98-76c2-a96e
# import-link-transitivity-req: -l${_l} alone only satisfies THIS
# module's own direct reference -- ${_l}'s own transitive deps (its
# lib${_l}.linkdeps, written by that module itself, whether compiled or
# imported) are appended too, so a consumer never has to list them by
# hand. No found-guard against the same name resolving in more than one
# _LIB_SEARCH_DIRS entry -- duplicate -l/-L flags are harmless.
# @impl 0f87-6ab5-8e46-cfb1
.for _l in ${LIBS}
LDFLAGS += -l${_l}
.  for _d in ${_LIB_SEARCH_DIRS}
.    if exists(${_d}/lib${_l}.linkdeps)
_LINKDEPS.${_l} != cat ${_d}/lib${_l}.linkdeps
LDFLAGS += ${_LINKDEPS.${_l}}
.    endif
.  endfor
.endfor

_OBJDIR = ${.CURDIR}/${OBJDIR}
_LIBOUT_DIR = ${.CURDIR}/${LIBDIR_LOCAL}

# ---------------------------------------------------------------------------
# IMPORT= -- this module imports a prebuilt library instead of compiling
# SRCS (imported-libraries-are-ordinary-modules-req). LIB_SHARED= is
# ignored for an import: whatever lib${LIB}.{a,so*,dylib} files the
# resolved source actually has are staged, not a choice this project
# makes. Resolution is a four-step ladder, first match wins
# (import-resolution-ladder-req):
#   1. env/CLI: ${LIB:tu}_PREFIX, or ${LIB:tu}_CFLAGS + ${LIB:tu}_LIBS
#   2. mk/ hooks: IMPORT_PREFIX, or IMPORT_CFLAGS + IMPORT_LIBS
#   3. IMPORT=pkg:<name> via pkg-config, or IMPORT=prefix:<dir> directly
#   4. probing mk.paths.<os>.mk's own _TOOL_PREFIXES for lib${LIB}.*
# An unresolved import is a parse-time .error naming what was tried.
# Neither _IMPORT_CFLAGS nor _IMPORT_LIBS is added to this module's own
# CFLAGS/CXXFLAGS/LDFLAGS -- there is no compile/link step for an import,
# only header/library staging; _IMPORT_CFLAGS' -I dirs are where
# IMPORT_HEADERS= is searched, _IMPORT_LIBDIR is where lib${LIB}.* is
# copied from, and _IMPORT_LIBS is recorded for the link-transitivity
# mechanism (import-link-transitivity-req) to consume, not used here.
# @impl 0f87-6ab5-8aa6-c2d0
# ---------------------------------------------------------------------------
IMPORT ?=
IMPORT_HEADERS ?=
# fetch-import-source-req/fetch-import-binary-req: IMPORT=fetch:<label>
# (source) / fetch-bin:<label> (prebuilt release) -- see
# 26-fetched-external-sources.md. FETCH_URL= is one or more full URLs to
# the SAME distfile, tried in order; FETCH_PATCHES= names files under
# this module's own patches/, applied in order (source kind only).
FETCH_URL ?=
FETCH_PATCHES ?=

.if !empty(IMPORT)
_IMP_VAR = ${LIB:tu}

.  if defined(${_IMP_VAR}_PREFIX) && !empty(${_IMP_VAR}_PREFIX)
_IMPORT_SOURCE  = env:${_IMP_VAR}_PREFIX=${${_IMP_VAR}_PREFIX}
_IMPORT_CFLAGS  = -I${${_IMP_VAR}_PREFIX}/include
_IMPORT_LIBS    = -L${${_IMP_VAR}_PREFIX}/lib -l${LIB}
_IMPORT_LIBDIR  = ${${_IMP_VAR}_PREFIX}/lib
.  elif defined(${_IMP_VAR}_CFLAGS) || defined(${_IMP_VAR}_LIBS)
_IMPORT_SOURCE  = env:${_IMP_VAR}_CFLAGS/${_IMP_VAR}_LIBS
_IMPORT_CFLAGS  = ${${_IMP_VAR}_CFLAGS}
_IMPORT_LIBS    = ${${_IMP_VAR}_LIBS}
_IMPORT_LIBDIR  =
.  elif defined(IMPORT_PREFIX) && !empty(IMPORT_PREFIX)
_IMPORT_SOURCE  = hook:IMPORT_PREFIX=${IMPORT_PREFIX}
_IMPORT_CFLAGS  = -I${IMPORT_PREFIX}/include
_IMPORT_LIBS    = -L${IMPORT_PREFIX}/lib -l${LIB}
_IMPORT_LIBDIR  = ${IMPORT_PREFIX}/lib
.  elif (defined(IMPORT_CFLAGS) && !empty(IMPORT_CFLAGS)) || (defined(IMPORT_LIBS) && !empty(IMPORT_LIBS))
_IMPORT_SOURCE  = hook:IMPORT_CFLAGS/IMPORT_LIBS
_IMPORT_CFLAGS  = ${IMPORT_CFLAGS}
_IMPORT_LIBS    = ${IMPORT_LIBS}
_IMPORT_LIBDIR  =
.  elif ${IMPORT:C/:.*//} == "fetch"
# fetch-import-source-req: extracted (+patched) source becomes this
# module's own SRCS, compiled through the ordinary pipeline below --
# no _IMPORT_CFLAGS/_IMPORT_LIBS/_IMPORT_LIBDIR of its own (there is no
# prebuilt artifact to point at), only the resolved work-tree root.
# @impl 0f87-6ab6-4fe1-98d2
_IMPORT_FETCH_LABEL = ${IMPORT:C/^[^:]*://}
_IMPORT_SOURCE  = fetch:${_IMPORT_FETCH_LABEL}
_IMPORT_KIND    = source
_IMPORT_WRKSRC  = ${.CURDIR}/work/_resolved
.  elif ${IMPORT:C/:.*//} == "fetch-bin"
# fetch-import-binary-req: same fetch/verify/extract/patch pipeline,
# but the resolved work tree is treated as a conventional prefix
# (include/, lib/) and staged via the SAME _stage_import: mechanism
# pkg:/prefix: already use -- no compiling.
# @impl 0f87-6ab6-4fe1-98d2
_IMPORT_FETCH_LABEL = ${IMPORT:C/^[^:]*://}
_IMPORT_SOURCE  = fetch-bin:${_IMPORT_FETCH_LABEL}
_IMPORT_KIND    = binary
_IMPORT_WRKSRC  = ${.CURDIR}/work/_resolved
_IMPORT_CFLAGS  = -I${_IMPORT_WRKSRC}/include
_IMPORT_LIBS    = -L${_IMPORT_WRKSRC}/lib -l${LIB}
_IMPORT_LIBDIR  = ${_IMPORT_WRKSRC}/lib
.  elif ${IMPORT:C/:.*//} == "pkg"
_IMPORT_PKGNAME = ${IMPORT:C/^[^:]*://}
# Cross-compilation: never read host .pc files; sysroot-aware per
# BMK_<OS>_SYSROOT= (the same variable mk.toolchain.llvm.mk's own cross
# branches already require) -- implemented per the brief's own explicit
# requirement, not empirically verified end-to-end (no foreign sysroot
# with real .pc files available from this host; cross-compilation itself
# is out of scope this round beyond keeping this behavior correct).
.    if ${TARGET} != ${_HOST_OS_LABEL}
_IMPORT_SYSROOT = ${BMK_${TARGET:tu}_SYSROOT}
_IMPORT_PC_ENV  = env PKG_CONFIG_SYSROOT_DIR="${_IMPORT_SYSROOT}" PKG_CONFIG_LIBDIR="${_IMPORT_SYSROOT}/usr/lib/pkgconfig:${_IMPORT_SYSROOT}/usr/share/pkgconfig" PKG_CONFIG_PATH=
.    else
# Additive, not replacing: a real install found via pkg-config's own
# built-in default search paths (e.g. MacPorts pkg-config already
# defaulting to /opt/local/lib/pkgconfig) must keep working with zero
# Bmake It configuration -- PKG_CONFIG_LIBDIR (which REPLACES the
# built-in defaults, unlike PKG_CONFIG_PATH) is deliberately left alone
# here; only the cross-compiling branch above sets it. The caller's own
# inherited PKG_CONFIG_PATH (if any) is kept and extended, not discarded
# -- converted to a bmake word list and back so the join is correct
# whether or not either half is empty.
_IMPORT_PC_PATH = ${_PKG_CONFIG_EXTRA_DIRS} ${PKG_CONFIG_PATH:S/:/ /g}
_IMPORT_PC_ENV  = env PKG_CONFIG_PATH="${_IMPORT_PC_PATH:ts:}"
.    endif
# @impl 0f87-6ab6-0d63-eb19
# import-resolution-cache-req: "does a second build re-resolve" is a
# real question, distinct from item 4's own staging cache -- pkg-config
# is a subprocess call, worth skipping when nothing relevant to IT
# changed, even though *staging* was already cheap to skip via
# INPUTS_HASH_EXTRA. Cache key: everything the pkg-config call itself
# depends on (IMPORT=, PKG_CONFIG_PATH, the extra-dirs list, TARGET/
# TARGET_ARCH) -- NOT the resolved .pc file's own content/mtime, which
# would need locating the .pc file first (a chicken-and-egg problem: you
# can't skip the lookup to find what you'd need to detect if the lookup
# result changed). So this cache correctly detects a changed env/hook/
# PKG_CONFIG_PATH, but not a package silently upgraded in place with no
# such change -- a known, narrower limitation than a content-aware
# cache, not a correctness bug for what it does cover.
_IMPORT_CACHE_FILE = ${.CURDIR}/${BUILD_ROOT}/.import-resolve-cache
_IMPORT_FP != printf '%s' "IMPORT=${IMPORT} PKG_CONFIG_PATH=${PKG_CONFIG_PATH} EXTRA=${_PKG_CONFIG_EXTRA_DIRS} TARGET=${TARGET} TARGET_ARCH=${TARGET_ARCH}" | cksum
.    if exists(${_IMPORT_CACHE_FILE})
_IMPORT_FP_CACHED != sed -n '1p' ${_IMPORT_CACHE_FILE} 2>/dev/null
.    else
_IMPORT_FP_CACHED =
.    endif
.    if ${_IMPORT_FP_CACHED} == ${_IMPORT_FP}
# Cache hit: read the previously-resolved values back, no pkg-config
# call this time. Mirrors the non-cached branch's own guard exactly --
# a cached "not found" must leave _IMPORT_SOURCE genuinely undefined
# too, or step 4 (probing) and the final .error would be silently
# skipped in favor of a defined-but-empty resolution.
_IMPORT_PC_FOUND != sed -n '2p' ${_IMPORT_CACHE_FILE}
.      if ${_IMPORT_PC_FOUND} == "yes"
_IMPORT_VERSION != sed -n '3p' ${_IMPORT_CACHE_FILE}
_IMPORT_SOURCE  != sed -n '4p' ${_IMPORT_CACHE_FILE}
_IMPORT_CFLAGS  != sed -n '5p' ${_IMPORT_CACHE_FILE}
_IMPORT_LIBS    != sed -n '6p' ${_IMPORT_CACHE_FILE}
_IMPORT_LIBDIR  != sed -n '7p' ${_IMPORT_CACHE_FILE}
.      endif
.    else
_IMPORT_PC_FOUND != ${_IMPORT_PC_ENV} pkg-config --exists ${_IMPORT_PKGNAME} 2>/dev/null && echo yes || echo no
.      if ${_IMPORT_PC_FOUND} == "yes"
_IMPORT_VERSION != ${_IMPORT_PC_ENV} pkg-config --modversion ${_IMPORT_PKGNAME} 2>/dev/null
_IMPORT_SOURCE   = pkg-config:${_IMPORT_PKGNAME}(${_IMPORT_VERSION})
_IMPORT_CFLAGS  != ${_IMPORT_PC_ENV} pkg-config --cflags ${_IMPORT_PKGNAME} 2>/dev/null
# --static also pulls in Libs.private -- the transitive link deps this
# module's own consumers need (D2, import-link-transitivity-req).
_IMPORT_LIBS    != ${_IMPORT_PC_ENV} pkg-config --libs --static ${_IMPORT_PKGNAME} 2>/dev/null
_IMPORT_LIBDIR  != ${_IMPORT_PC_ENV} pkg-config --variable=libdir ${_IMPORT_PKGNAME} 2>/dev/null
.      endif
# Write the cache regardless of hit/miss on _IMPORT_PC_FOUND itself --
# a genuine "not found" is just as valid to cache as a genuine "found"
# (a second build shouldn't re-probe pkg-config just to re-learn the
# same absence either).
_IMPORT_CACHE_WRITE != mkdir -p ${.CURDIR}/${BUILD_ROOT} && { echo '${_IMPORT_FP}'; echo '${_IMPORT_PC_FOUND}'; echo '${_IMPORT_VERSION}'; echo '${_IMPORT_SOURCE}'; echo '${_IMPORT_CFLAGS}'; echo '${_IMPORT_LIBS}'; echo '${_IMPORT_LIBDIR}'; } > ${_IMPORT_CACHE_FILE}; echo ok
.    endif
.  elif ${IMPORT:C/:.*//} == "prefix"
_IMPORT_PREFIX_VAL = ${IMPORT:C/^[^:]*://}
_IMPORT_SOURCE  = prefix:${_IMPORT_PREFIX_VAL}
_IMPORT_CFLAGS  = -I${_IMPORT_PREFIX_VAL}/include
_IMPORT_LIBS    = -L${_IMPORT_PREFIX_VAL}/lib -l${LIB}
_IMPORT_LIBDIR  = ${_IMPORT_PREFIX_VAL}/lib
.  endif

# Step 4: probing, only if still unresolved by any of the above.
.  if !defined(_IMPORT_SOURCE)
.    for _p in ${_TOOL_PREFIXES:H:O:u}
.      if !defined(_IMPORT_SOURCE) && (exists(${_p}/lib/lib${LIB}.a) || exists(${_p}/lib/lib${LIB}.so) || exists(${_p}/lib/lib${LIB}.dylib))
_IMPORT_SOURCE  = probe:${_p}
_IMPORT_CFLAGS  = -I${_p}/include
_IMPORT_LIBS    = -L${_p}/lib -l${LIB}
_IMPORT_LIBDIR  = ${_p}/lib
.      endif
.    endfor
.  endif

.  if !defined(_IMPORT_SOURCE)
.error "IMPORT=${IMPORT}: cannot resolve module ${.CURDIR:T} (LIB=${LIB}) for target ${OS_ARCH} -- tried ${_IMP_VAR}_PREFIX/${_IMP_VAR}_CFLAGS+${_IMP_VAR}_LIBS (env), IMPORT_PREFIX/IMPORT_CFLAGS+IMPORT_LIBS (mk/ hooks), pkg-config, and probing ${_TOOL_PREFIXES:H:O:u} -- install the library via your host's package manager (see README.md Prerequisites) or set ${_IMP_VAR}_PREFIX=/path/to/prefix"
.  endif

# import-staging-req: re-stage whenever the resolved inputs change,
# reusing item 4's own mechanism rather than inventing a second cache.
INPUTS_HASH_EXTRA += IMPORT=${_IMPORT_SOURCE} IMPORT_CFLAGS=${_IMPORT_CFLAGS} IMPORT_LIBS=${_IMPORT_LIBS}
.endif

# fetch-import-source-req: an IMPORT=fetch: module's SRCS= are relative
# to the resolved work tree, not src/ -- _fetch_import: (below) makes
# ${_IMPORT_WRKSRC} real before anything tries to read from it, and re-
# extraction there also clears ${_OBJDIR} so a changed fetch always
# forces a real recompile (not left to a source-mtime race against a
# distfile's own, possibly old, embedded timestamps).
# @impl 0f87-6ab6-4fe1-98d2
.if ${_IMPORT_KIND:Uno} == "source"
_SRC_BASE = ${_IMPORT_WRKSRC}
_FETCH_PREREQ = _fetch_import
.else
_SRC_BASE = ${.CURDIR}/src
_FETCH_PREREQ =
.endif

# @impl 0f87-6a98-76ed-e260
.if ${TARGET} == "macos"
SHLIB_NAME     = lib${LIB}.${SHLIB_MAJOR}.dylib
SHLIB_LINK     = lib${LIB}.dylib
# @impl 0f87-6aa9-448d-537c -- @rpath, not a bare filename, so a matching
# consumer-side -Wl,-rpath (below, and in mk.prog.mk/mk.test.mk) can find it
_SHLIB_LDFLAGS = -dynamiclib -install_name @rpath/${SHLIB_NAME} -compatibility_version ${SHLIB_MAJOR} -current_version ${SHLIB_MAJOR}
# @impl 0f87-6a98-96de-331e
.elif ${TARGET} == "win"
# No "lib" prefix and no SONAME-style major-version suffix (neither is a
# Windows convention -- LIB= already strips a leading "lib" project-wide,
# so this falls out naturally); the toolchain-agnostic -shared/--out-implib
# flags below are translated per-toolchain (msvc-cc-wrapper.sh for
# TOOLCHAIN=msvc, understood natively by Cygwin/mingw gcc or clang).
SHLIB_NAME     = ${LIB}.dll
SHLIB_LINK     = ${LIB}.dll
_SHLIB_LDFLAGS = -shared -Wl,--out-implib,${_LIBOUT_DIR}/${LIB}.lib
.else
SHLIB_NAME     = lib${LIB}.so.${SHLIB_MAJOR}
SHLIB_LINK     = lib${LIB}.so
_SHLIB_LDFLAGS = -shared -Wl,-soname,${SHLIB_NAME}
.endif

.if ${TARGET} == "win"
STATIC_NAME = ${LIB}.lib
.else
STATIC_NAME = lib${LIB}.a
.endif

OBJS =
.for _s in ${SRCS}
OBJS += ${_OBJDIR}/${_s:R}.o
.endfor

_create_dirs:
	@mkdir -p ${_OBJDIR} ${_LIBOUT_DIR} ${.CURDIR}/${INCDIR_LOCAL}

.for _s in ${SRCS}
.  if ${_s:E} == "c"
${_OBJDIR}/${_s:R}.o: ${_FETCH_PREREQ} ${_SRC_BASE}/${_s} ${_INPUTS_HASH_FILE}
	${CC} ${CFLAGS} ${_DEP_CFLAGS} ${_DEP_CFLAGS:D-MF ${_OBJDIR}/${_s:R}.d} -fPIC -c ${_SRC_BASE}/${_s} -o ${.TARGET}
.  elif !empty(_CXX_EXTS:M${_s:E})
${_OBJDIR}/${_s:R}.o: ${_FETCH_PREREQ} ${_SRC_BASE}/${_s} ${_INPUTS_HASH_FILE}
	${CXX} ${CXXFLAGS} ${_DEP_CFLAGS} ${_DEP_CFLAGS:D-MF ${_OBJDIR}/${_s:R}.d} -fPIC -c ${_SRC_BASE}/${_s} -o ${.TARGET}
.  elif ${_s:E} == "y"
${_OBJDIR}/${_s:R}.c: ${_FETCH_PREREQ} ${_SRC_BASE}/${_s}
	${YACC} ${YFLAGS} -d -o ${.TARGET} ${_SRC_BASE}/${_s}
	@if [ -f y.tab.h ]; then mv y.tab.h ${_OBJDIR}/${_s:R}.h; fi
	@mkdir -p ${.CURDIR}/${INCDIR_LOCAL}
	@if [ -f ${_OBJDIR}/${_s:R}.h ]; then cp -f ${_OBJDIR}/${_s:R}.h ${.CURDIR}/${INCDIR_LOCAL}/; fi
${_OBJDIR}/${_s:R}.o: ${_OBJDIR}/${_s:R}.c ${_INPUTS_HASH_FILE}
	${CC} ${CFLAGS} ${_DEP_CFLAGS} ${_DEP_CFLAGS:D-MF ${_OBJDIR}/${_s:R}.d} -fPIC -c ${_OBJDIR}/${_s:R}.c -o ${.TARGET}
.  elif ${_s:E} == "l"
${_OBJDIR}/${_s:R}.c: ${_FETCH_PREREQ} ${_SRC_BASE}/${_s}
	${LEX} ${LFLAGS} -o ${.TARGET} ${_SRC_BASE}/${_s}
${_OBJDIR}/${_s:R}.o: ${_OBJDIR}/${_s:R}.c ${_INPUTS_HASH_FILE}
	${CC} ${CFLAGS} ${_DEP_CFLAGS} ${_DEP_CFLAGS:D-MF ${_OBJDIR}/${_s:R}.d} -fPIC -c ${_OBJDIR}/${_s:R}.c -o ${.TARGET}
.  endif
# header-dependency-tracking-req: see mk.prog.mk's identical comment.
.  if exists(${_OBJDIR}/${_s:R}.d)
.    include "${_OBJDIR}/${_s:R}.d"
.  endif
.endfor

.if ${_IMPORT_KIND:Uno} == "source"
# fetch-import-source-req: an ordinary compiled-library build (SHLIB_NAME/
# STATIC_NAME from OBJS, exactly like a non-IMPORT= module), plus header
# staging from the resolved fetched tree instead of INCL=/generated
# headers. _fetch_import already ran as a prerequisite of each .o: above.
.  if ${LIB_SHARED} == "YES"
all: _check_inputs_hash _create_dirs ${_LIBOUT_DIR}/${SHLIB_NAME} _stage_fetch_headers _write_linkdeps
	@echo "===> built shared ${SHLIB_NAME} (fetched: ${_IMPORT_SOURCE})"
.  else
all: _check_inputs_hash _create_dirs ${_LIBOUT_DIR}/${STATIC_NAME} _stage_fetch_headers _write_linkdeps
	@echo "===> built static ${STATIC_NAME} (fetched: ${_IMPORT_SOURCE})"
.  endif
.elif !empty(IMPORT)
all: _check_inputs_hash _create_dirs _fetch_import _stage_import _write_linkdeps
	@echo "===> imported ${LIB} (${_IMPORT_SOURCE})"
.elif ${LIB_SHARED} == "YES"
all: _check_inputs_hash _create_dirs ${_LIBOUT_DIR}/${SHLIB_NAME} _promote_incl _write_linkdeps
	@echo "===> built shared ${SHLIB_NAME}"
.else
all: _check_inputs_hash _create_dirs ${_LIBOUT_DIR}/${STATIC_NAME} _promote_incl _write_linkdeps
	@echo "===> built static ${STATIC_NAME}"
.endif

# import-link-transitivity-req: this module's OWN flattened direct link
# deps -- an imported library's is _IMPORT_LIBS (pkg-config's own
# --libs --static, already the correct transitive set for that package)
# minus its own self -l${LIB}/-L<owndir> tokens; a compiled library's is
# its own LIBS=, computed the SAME way the consumer-side loop above
# does (into a dedicated variable, not by filtering the shared LDFLAGS
# pot, which also holds unrelated things like -Wl,-rpath, entries) --
# recursive by construction: build order guarantees a dependency's own
# .linkdeps already exists by the time this runs.
# @impl 0f87-6ab5-8e46-cfb1
# fetch-import-source-req: a source-fetched (compiled) module is an
# ORDINARY compiled module for linkdeps purposes too -- its own LIBS=
# (unchanged mechanism), not _IMPORT_LIBS (undefined for the source
# kind; there is no prebuilt artifact to derive link flags from).
.if !empty(IMPORT) && ${_IMPORT_KIND:Uno} != "source"
_OWN_LINKDEPS = ${_IMPORT_LIBS:N-l${LIB}:N-L${_IMPORT_LIBDIR}}
.else
_OWN_LINKDEPS =
.  for _l in ${LIBS}
_OWN_LINKDEPS += -l${_l}
.    for _d in ${_LIB_SEARCH_DIRS}
.      if exists(${_d}/lib${_l}.linkdeps)
_OWN_LINKDEPS += ${_LINKDEPS.${_l}}
.      endif
.    endfor
.  endfor
.endif

_write_linkdeps:
	@echo "${_OWN_LINKDEPS}" > ${_LIBOUT_DIR}/lib${LIB}.linkdeps

# import-staging-req: only IMPORT_HEADERS= is staged (never the whole
# resolved include dir -- that would leak every unrelated package under
# it and defeat PREREQS=-based visibility), copied (not symlinked, D6)
# into the same destination promoted generated headers already use.
# lib${LIB}.* is copied into this module's own build/<KEY>/lib/, exactly
# where a compiled library's own AR/link recipe would have written it --
# so LIBS=<lib> in a consumer needs no changes at all (import-staging-req).
# Every lib${LIB}.* entry is classified by its OWN basename (not by the
# search extension, since macOS puts the version before the extension --
# libfoo.34.dylib -- while ELF puts it after -- libfoo.so.34 -- so an
# extension-anchored glob misses the macOS form entirely): a symlink is
# followed to its real underlying file (relative or absolute target,
# possibly multiple hops) and recreated fresh as a same-directory
# relative symlink pointing at that file's basename, never copied
# verbatim -- copying a real prefix's symlink as-is either goes dangling
# (its target's name doesn't match the glob that found it) or leaks an
# absolute path back into the original install, both observed producing
# broken dylib symlinks in staged builds against real macOS packages
# (PDAL/GDAL/GLFW) before this fix (import-staging-broken-dylib-symlinks-obs).
# @impl 0f87-6ab5-8aa6-c2d0
# @impl 0f87-6ab6-60c6-d25a
_stage_import:
	@mkdir -p ${_FWDIR}/${BUILD_ROOT}/include ${_LIBOUT_DIR}
	@echo "===> IMPORT=${IMPORT}: resolved via ${_IMPORT_SOURCE}"
.for _h in ${IMPORT_HEADERS}
	@_found=no; \
	for _d in ${_IMPORT_CFLAGS:M-I*:S/-I//}; do \
		if [ -e "$$_d/${_h}" ]; then \
			cp -a "$$_d/${_h}" ${_FWDIR}/${BUILD_ROOT}/include/; \
			echo "===> staged header ${_h} from $$_d"; \
			_found=yes; \
			break; \
		fi; \
	done; \
	if [ "$$_found" = no ]; then \
		echo "error: IMPORT_HEADERS=${_h}: not found under any resolved include dir (${_IMPORT_CFLAGS})" >&2; \
		exit 1; \
	fi
.endfor
	@if [ -z "${_IMPORT_LIBDIR}" ]; then \
		echo "===> IMPORT=${IMPORT}: no resolved library directory (env/hook CFLAGS+LIBS mode) -- skipping lib${LIB}.* staging; consumers relying on LIBS=${LIB} need _PREFIX-style resolution instead" >&2; \
	else \
		_found=no; \
		for _f in "${_IMPORT_LIBDIR}"/lib${LIB}.*; do \
			[ -e "$$_f" ] || continue; \
			_base=$$(basename "$$_f"); \
			case "$$_base" in \
				*.a|*.so|*.so.*|*.dylib) ;; \
				*) continue ;; \
			esac; \
			_found=yes; \
			if [ -L "$$_f" ]; then \
				_real=$$_f; \
				while [ -L "$$_real" ]; do \
					_target=$$(readlink "$$_real"); \
					case "$$_target" in \
						/*) _real=$$_target ;; \
						*) _real=$$(dirname "$$_real")/$$_target ;; \
					esac; \
				done; \
				if [ -f "$$_real" ]; then \
					ln -sf "$$(basename "$$_real")" "${_LIBOUT_DIR}/$$_base"; \
				fi; \
			else \
				cp -a "$$_f" "${_LIBOUT_DIR}/$$_base"; \
			fi; \
		done; \
		if [ "$$_found" = no ]; then \
			echo "error: IMPORT=${IMPORT}: lib${LIB}.{a,so,dylib} not found in resolved libdir ${_IMPORT_LIBDIR}" >&2; \
			exit 1; \
		fi; \
	fi

# fetch-import-source-req/fetch-import-binary-req/fetch-distinfo-
# checksum-req/fetch-cache-never-committed-req (26-fetched-external-
# sources.md): fetch, verify (SHA-256 against the committed distinfo,
# not this project's own cksum -- a materially weaker guarantee, wrong
# tool for verifying untrusted downloaded content), extract, and patch
# a distfile. distfiles/ (the raw download) and work/ (the extraction,
# including the fixed work/_resolved/ this module's own SRCS=/staging
# read from) are per-module, gitignored, never committed -- only this
# recipe, FETCH_URL=/FETCH_PATCHES=, and the committed distinfo/patches/
# themselves are. A no-op for every IMPORT= kind except fetch:/fetch-bin:
# (always a prerequisite of all: regardless of kind, simplest to keep
# one shared entry point rather than conditionally omitting it).
# Idempotent via a fingerprint marker (work/.extract-fp): re-fetches/
# re-extracts/re-patches only when FETCH_URL=/FETCH_PATCHES= actually
# changed, and clears ${_OBJDIR} on a genuine re-extraction so a stale
# .o can never survive a source change via an mtime race against a
# distfile's own (possibly old) embedded timestamps.
# @impl 0f87-6ab6-4fe1-98d2
_fetch_import:
.if ${_IMPORT_KIND:Uno} != "source" && ${_IMPORT_KIND:Uno} != "binary"
	@:
.else
	@mkdir -p ${.CURDIR}/distfiles ${.CURDIR}/work
	@_fp=$$(printf '%s' "URL=${FETCH_URL} PATCHES=${FETCH_PATCHES}" | cksum); \
	if [ -f ${.CURDIR}/work/.extract-fp ] && [ "$$(cat ${.CURDIR}/work/.extract-fp)" = "$$_fp" ]; then \
		exit 0; \
	fi; \
	_basename=""; \
	for _url in ${FETCH_URL}; do \
		_base=$$(basename "$$_url"); \
		_dist=${.CURDIR}/distfiles/$$_base; \
		if [ ! -f "$$_dist" ]; then \
			echo "===> fetching $$_url"; \
			if command -v curl >/dev/null 2>&1; then \
				curl -fsSL -o "$$_dist.tmp" "$$_url" 2>/dev/null || { rm -f "$$_dist.tmp"; continue; }; \
			elif command -v wget >/dev/null 2>&1; then \
				wget -q -O "$$_dist.tmp" "$$_url" 2>/dev/null || { rm -f "$$_dist.tmp"; continue; }; \
			else \
				echo "error: IMPORT=${IMPORT}: neither curl nor wget found on PATH -- cannot fetch $$_url" >&2; exit 1; \
			fi; \
			mv "$$_dist.tmp" "$$_dist"; \
		fi; \
		_basename=$$_base; \
		break; \
	done; \
	if [ -z "$$_basename" ]; then \
		echo "error: IMPORT=${IMPORT}: could not fetch any of: ${FETCH_URL}" >&2; \
		exit 1; \
	fi; \
	_dist=${.CURDIR}/distfiles/$$_basename; \
	_distinfo=${.CURDIR}/distinfo; \
	if [ ! -f "$$_distinfo" ]; then \
		echo "error: IMPORT=${IMPORT}: no distinfo file at $$_distinfo -- run whatever generates it (see 26-fetched-external-sources.md) before fetching" >&2; \
		exit 1; \
	fi; \
	_expected=$$(awk -v f="$$_basename" '$$1=="SHA256" && $$2=="(" f ")" {print $$4}' "$$_distinfo"); \
	if [ -z "$$_expected" ]; then \
		echo "error: IMPORT=${IMPORT}: no SHA256 entry for $$_basename in $$_distinfo" >&2; \
		exit 1; \
	fi; \
	_actual=$$( (sha256sum "$$_dist" 2>/dev/null || shasum -a 256 "$$_dist" 2>/dev/null) | awk '{print $$1}'); \
	if [ "$$_actual" != "$$_expected" ]; then \
		echo "error: IMPORT=${IMPORT}: checksum mismatch for $$_basename -- expected $$_expected, got $$_actual (corrupted download or distinfo out of date)" >&2; \
		rm -f "$$_dist"; \
		exit 1; \
	fi; \
	echo "===> verified $$_basename (sha256 ok)"; \
	rm -rf ${.CURDIR}/work/_extracted ${.CURDIR}/work/_resolved; \
	mkdir -p ${.CURDIR}/work/_extracted; \
	case "$$_basename" in \
		*.zip) unzip -q "$$_dist" -d ${.CURDIR}/work/_extracted ;; \
		*) tar xf "$$_dist" -C ${.CURDIR}/work/_extracted ;; \
	esac; \
	_n=$$(find ${.CURDIR}/work/_extracted -mindepth 1 -maxdepth 1 | wc -l | tr -d ' '); \
	_only=$$(find ${.CURDIR}/work/_extracted -mindepth 1 -maxdepth 1); \
	if [ "$$_n" = "1" ] && [ -d "$$_only" ]; then \
		_wrksrc=$$_only; \
	else \
		_wrksrc=${.CURDIR}/work/_extracted; \
	fi; \
	cp -a "$$_wrksrc" ${.CURDIR}/work/_resolved; \
	for _p in ${FETCH_PATCHES}; do \
		echo "===> applying patch $$_p"; \
		patch -p1 -d ${.CURDIR}/work/_resolved < ${.CURDIR}/patches/$$_p || { \
			echo "error: IMPORT=${IMPORT}: patch $$_p failed to apply" >&2; exit 1; \
		}; \
	done; \
	rm -rf ${_OBJDIR}; \
	mkdir -p ${_OBJDIR}; \
	echo "$$_fp" > ${.CURDIR}/work/.extract-fp; \
	echo "===> fetched+extracted $$_basename (${IMPORT})"
.endif

# fetch-import-source-req: header staging for the SOURCE kind, reusing
# IMPORT_HEADERS= and the SAME search-and-copy shell logic _stage_import:
# already uses -- just against the fetched work tree instead of a
# resolved prefix, and without the lib${LIB}.* half (compiling produces
# that, via the ordinary ${_LIBOUT_DIR}/${SHLIB_NAME}/${STATIC_NAME}
# recipes below).
# @impl 0f87-6ab6-4fe1-98d2
_stage_fetch_headers:
.if !empty(IMPORT_HEADERS)
	@mkdir -p ${_FWDIR}/${BUILD_ROOT}/include
.for _h in ${IMPORT_HEADERS}
	@_found=no; \
	for _d in ${_IMPORT_WRKSRC} ${_IMPORT_WRKSRC}/include; do \
		if [ -e "$$_d/${_h}" ]; then \
			cp -a "$$_d/${_h}" ${_FWDIR}/${BUILD_ROOT}/include/; \
			echo "===> staged header ${_h} from $$_d"; \
			_found=yes; \
			break; \
		fi; \
	done; \
	if [ "$$_found" = no ]; then \
		echo "error: IMPORT_HEADERS=${_h}: not found under the fetched work tree (${_IMPORT_WRKSRC} or its include/)" >&2; \
		exit 1; \
	fi
.endfor
.endif

# @impl 0f87-6a98-8b7f-9215
${_LIBOUT_DIR}/${SHLIB_NAME}: ${OBJS}
.for _l in ${LIBS}
	@_found=no; \
	for _d in ${_LIB_SEARCH_DIRS}; do \
		if [ -f "$$_d/lib${_l}.a" ] || [ -f "$$_d/lib${_l}.so" ] || [ -f "$$_d/lib${_l}.dylib" ] || [ -f "$$_d/${_l}.lib" ]; then \
			_found=yes; break; \
		fi; \
	done; \
	if [ "$$_found" = no ]; then \
		echo "error: cannot link lib${LIB}: prerequisite library ${_l} (from LIBS=) has not been built yet -- searched: ${_LIB_SEARCH_DIRS}" >&2; \
		exit 1; \
	fi
.endfor
	${_CCLINK} ${_SHLIB_LDFLAGS} -o ${.TARGET} ${OBJS} ${LDFLAGS}
.if ${TARGET} != "win"
	@ln -sfn ${SHLIB_NAME} ${_LIBOUT_DIR}/${SHLIB_LINK} 2>/dev/null || cp -f ${.TARGET} ${_LIBOUT_DIR}/${SHLIB_LINK}
	@${AR} rcs ${_LIBOUT_DIR}/${STATIC_NAME} ${OBJS}
.endif
# win: SHLIB_LINK == SHLIB_NAME (no separate unversioned symlink target on
# Windows), and STATIC_NAME == the import library link.exe's own
# --out-implib already wrote via _SHLIB_LDFLAGS above -- both lines above
# would be redundant-to-harmful (the AR line would silently overwrite the
# import lib with a plain static archive of the same objects) so are
# skipped entirely for win, not just no-ops.

${_LIBOUT_DIR}/${STATIC_NAME}: ${OBJS}
	${AR} rcs ${.TARGET} ${OBJS}

# @impl 0f87-6a98-7718-886d
_promote_incl:
.if defined(INCL) && !empty(INCL)
	@mkdir -p ${_FWDIR}/${BUILD_ROOT}/include
.  for _h in ${INCL}
	@if [ -f ${.CURDIR}/${INCDIR_LOCAL}/${_h} ]; then \
		cp -f ${.CURDIR}/${INCDIR_LOCAL}/${_h} ${_FWDIR}/${BUILD_ROOT}/include/; \
		echo "===> promoted ${_h}"; \
	elif [ -f ${_OBJDIR}/${_h} ]; then \
		cp -f ${_OBJDIR}/${_h} ${_FWDIR}/${BUILD_ROOT}/include/; \
		echo "===> promoted ${_h}"; \
	fi
.  endfor
.endif

# @impl 0f87-6a98-8ee9-ae83
copy-up: all
	@sh ${BMK_MKDIR}/../scripts/diff-aware-copy.sh ${_LIBOUT_DIR} ${_FWDIR}/${LIBDIR_LOCAL}
	@echo "===> copy-up lib${LIB} → framework ${LIBDIR_LOCAL}/"

clean:
.if ${CLEAN_ALL_TARGETS} == "yes"
	rm -rf ${.CURDIR}/build
.else
	rm -rf ${.CURDIR}/${BUILD_ROOT}
.endif
	rm -f *.o *.obj *.core *.dylib *.so *.so.* *.a *.lib *.dll 2>/dev/null || true
	rm -f ${.CURDIR}/.gen-mod-order.mk ${.CURDIR}/.depend 2>/dev/null || true
	# fetch-cache-never-committed-req: work/ (extraction scratch) is
	# build-output-like -- always removed. distfiles/ (the downloaded
	# archive itself) is a cache that's expensive to refetch, so it's
	# only dropped under CLEAN_ALL_TARGETS=yes, mirroring real ports'
	# own clean/distclean split. patches/ is committed source, never
	# touched by clean.
	# @impl 0f87-6ab6-4fe1-98d2
	rm -rf ${.CURDIR}/work
.if ${CLEAN_ALL_TARGETS} == "yes"
	rm -rf ${.CURDIR}/distfiles
.endif


.include "${BMK_MKDIR}/mk.test.mk"

_LOCAL_MK_PHASE = local
.include "${BMK_MKDIR}/mk.local.mk"

BMK_HELP_ROLE = lib
.include "${BMK_MKDIR}/mk.help.mk"

.PHONY: all clean help copy-up _create_dirs _promote_incl _stage_import _fetch_import _stage_fetch_headers _write_linkdeps help
.endif

