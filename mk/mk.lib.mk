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

# fetch-build-forwarding-fix-req: a snapshot of LDFLAGS taken right here,
# before any of THIS file's own consumer-side additions below (LIBS=/
# PREREQS= -L/-l/-Wl,-rpath, entries) -- so _fetch_build: can forward
# just the toolchain-level contribution (SANITIZE=/OPENMP=) to an
# upstream build, not this module's own link flags for linking against
# sibling frameworks/prereqs. Forwarding the full, later LDFLAGS broke
# CMake's own "Check for working C compiler" step (an unrelated/stale
# -l<name> or -Wl,-rpath, entry made CMake's own trial link fail).
# @impl 0f87-6aba-a53b-3097
_TOOLCHAIN_LDFLAGS = ${LDFLAGS}

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
.include "${BMK_MKDIR}/mk.requires.mk"

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
# own #if resolves to export here and import there. LIB= is a free-form
# name (a fetched project's own upstream name, e.g. "laz-perf"), not
# necessarily a valid C identifier once uppercased -- every character
# that isn't [A-Za-z0-9_] is replaced with _ first (found empirically: a
# dashed LIB= produced -DLAZ-PERF_BUILDING, not one valid macro define
# but two broken compiler arguments).
# @impl 0f87-6aba-a30f-2123
_LIB_MACRO_NAME = ${LIB:tu:C/[^A-Za-z0-9_]/_/g}
CFLAGS   += -D${_LIB_MACRO_NAME}_BUILDING
CXXFLAGS += -D${_LIB_MACRO_NAME}_BUILDING

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
# easily pull in its own tests/examples/tools. Not required (and
# irrelevant) when FETCH_BUILD= delegates to the upstream project's own
# build system instead of Bmake It's own SRCS= pipeline
# (fetch-build-req).
.if ${IMPORT:Uno:C/:.*//} == "fetch" && (!defined(FETCH_BUILD) || empty(FETCH_BUILD))
.  if !defined(SRCS) || empty(SRCS)
.    error "IMPORT=${IMPORT}: SRCS= is required (paths relative to the fetched work tree) -- it is not auto-discovered for a fetched source, unlike an ordinary module's src/. Set FETCH_BUILD=autotools|cmake|meson|custom instead if this source builds with its own build system."
.  endif
.elif ${IMPORT:Uno:C/:.*//} == "fetch"
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

# prog-only-framework-ld-warning-fix-req: see mk.prog.mk's identical
# comment -- guarded the same way the PREREQS= loop just above already
# is, so the first lib module in a framework (nothing copied-up yet)
# doesn't produce a noisy, harmless `ld: warning: search path ... not
# found`.
# @impl 0f87-6abe-3f50-b644
.if exists(${_FWDIR}/${BUILD_ROOT}/lib)
LDFLAGS += -L${_FWDIR}/${BUILD_ROOT}/lib
.endif
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

# relink-on-libs-change-req: see mk.prog.mk's identical comment -- each
# LIBS= entry's actual resolved file (not just -l/-L flags) is a real
# make prerequisite of the shared-lib link below, so a library rebuilt
# elsewhere (including a PREREQS=-visible one in another framework)
# triggers a genuine relink, not just a link-time existence check.
# @impl 0f87-6aba-a303-153e
_LIBS_FILES =
.for _l in ${LIBS}
_LIB_FILE.${_l} != for _d in ${_LIB_SEARCH_DIRS}; do \
	for _f in "$$_d/lib${_l}.a" "$$_d/lib${_l}.so" "$$_d/lib${_l}.dylib" "$$_d/${_l}.lib"; do \
		if [ -f "$$_f" ]; then echo "$$_f"; break 2; fi; \
	done; \
done
_LIBS_FILES += ${_LIB_FILE.${_l}}
.endfor

# fetch-build-forwarding-fix-req: sibling FETCH_BUILD= modules' own
# install prefixes, so a fetch-built module's cmake/meson/autotools
# configure can find_package()/pkg-config another fetch-built module it
# depends on (found empirically: copc-lib's own cmake configure could
# not locate laz-perf, a sibling fetch-built module, without manual
# help) -- no new macro to declare this: every *.m module directory in
# THIS framework and every PREREQS=-visible framework is scanned by
# convention (matching how _LIB_SEARCH_DIRS itself is built) for a
# work/_install it may have already produced. An install prefix that
# doesn't apply to this particular module is harmless noise to a build
# tool's own search path, not an error.
# @impl 0f87-6aba-a53b-3097
_FETCH_SEARCH_FW_DIRS = ${_FWDIR}
.for _p in ${_PREREQS}
.  if defined(_PREREQ_BASE.${_p})
_FETCH_SEARCH_FW_DIRS += ${_PREREQ_BASE.${_p}}/${_p}
.  endif
.endfor
# single-module-visit-req: THIS module's own work/_install is excluded.
# It does not exist on the first parse and does on every later one, so
# including it made the FETCH_BUILD= fingerprint differ between a
# module's first and second build -- one spurious cmake reconfigure +
# rebuild on the second run. (The old build-then-copy-up double visit
# happened to absorb that one-time mismatch inside the first workspace
# build; with each module entered once it would otherwise surface on the
# user's next build.)
_FETCH_CMAKE_PREFIX_PATH != _pp=""; \
	_self=$$(cd ${.CURDIR} 2>/dev/null && pwd -P)/work/_install; \
	for _fw in ${_FETCH_SEARCH_FW_DIRS}; do \
		for _d in "$$_fw"/*.m/work/_install; do \
			[ -d "$$_d" ] || continue; \
			_real=$$(cd "$$_d" && pwd -P); \
			[ "$$_real" = "$$_self" ] && continue; \
			_pp="$$_pp$$_d;"; \
		done; \
	done; \
	printf '%s' "$$_pp"

# fetch-build-forwarding-fix-req: a native macOS build has no explicit
# deployment target anywhere (unlike a CROSS macos build, which already
# derives one from the SDK -- mk.toolchain.llvm.mk's _MACOS_MIN_VERSION)
# -- so a FETCH_BUILD= module's own CMake/Meson/autotools configure is
# free to pick a DIFFERENT default than whatever this project's own
# native objects end up with, producing linker warnings about mismatched
# minimum OS versions (found empirically). BMK_MACOS_MIN_VERSION=, if
# set, wins; otherwise clang's OWN ambient default for an unflagged
# native compile is probed directly (compile a trivial object, read its
# real LC_BUILD_VERSION minos back via otool -l) -- NOT the active SDK's
# own (higher) version, which is a DIFFERENT number (confirmed
# empirically: SDK 27.0, but an unflagged compile's own minos was 26.0
# -- querying the SDK version alone would have "fixed" the mismatch by
# moving it to the opposite side).
.if ${TARGET} == "macos"
.  if defined(BMK_MACOS_MIN_VERSION) && !empty(BMK_MACOS_MIN_VERSION)
_FETCH_MACOS_MIN_VERSION = ${BMK_MACOS_MIN_VERSION}
.  else
_FETCH_MACOS_MIN_VERSION != _t=$$(mktemp 2>/dev/null || echo /tmp/bmk-deploy-probe-$$$$); \
	printf 'int main(void){return 0;}' | ${CC:[1]} -x c - -o "$$_t" 2>/dev/null && \
	otool -l "$$_t" 2>/dev/null | awk '/minos/{print $$2; exit}'; \
	rm -f "$$_t"
.  endif
# A parse-time string, not a `.if` inside _fetch_build:'s own recipe --
# that recipe is one long backslash-continued shell script, and
# splitting it across a `.if`/`.endif` boundary is unproven/risky here;
# a plain variable substitution keeps the recipe a single, uninterrupted
# shell script on every TARGET.
_FETCH_DEPLOY_EXPORT = export MACOSX_DEPLOYMENT_TARGET="${_FETCH_MACOS_MIN_VERSION}";
.else
_FETCH_DEPLOY_EXPORT = :
.endif

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
# header-only-import-req: IMPORT_LIB=none declares a header-only import
# -- no lib<LIB>.{a,so,dylib} exists anywhere for it, by design (glm is
# the real case this came from: MacPorts' own optional compiled glm lib
# only made step 4's existing lib-file probe succeed by accident; a
# genuinely header-only glm, matching most installs, would never
# resolve). Step 4 probing's own success criterion switches from "a lib
# file exists" to "the first IMPORT_HEADERS= entry exists under this
# prefix's include/", and whatever DID resolve (pkg:/prefix:/probing)
# has its lib-staging suppressed regardless of what pkg-config or a
# probed prefix might otherwise have reported -- reusing
# _stage_import:'s own existing "_IMPORT_LIBDIR empty -> skip lib
# staging" branch (import-staging-req), not a new staging path.
# @impl 0f87-6abe-3f35-6680
IMPORT_LIB ?=
# fetch-import-source-req/fetch-import-binary-req: IMPORT=fetch:<label>
# (source) / fetch-bin:<label> (prebuilt release) -- see
# 26-fetched-external-sources.md. FETCH_URL= is one or more full URLs to
# the SAME distfile, tried in order; FETCH_PATCHES= names files under
# this module's own patches/, applied in order (source kind only).
FETCH_URL ?=
FETCH_PATCHES ?=
# fetch-build-req: when set on an IMPORT=fetch: module, the extracted
# (+patched) source is built with its OWN upstream build system instead
# of SRCS=/Bmake It's compile pipeline -- see 26-fetched-external-
# sources.md. FETCH_BUILD=autotools|cmake|meson runs a built-in default
# recipe installing into a module-local prefix; FETCH_BUILD=custom runs
# FETCH_BUILD_CMD= verbatim instead. Only meaningful together with
# IMPORT=fetch: (source kind) -- fetch-bin: already stages a prebuilt
# artifact directly, nothing to build.
FETCH_BUILD ?=
FETCH_BUILD_ARGS ?=
FETCH_BUILD_CMD ?=

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
.  elif ${IMPORT:C/:.*//} == "fetch" && (!defined(FETCH_BUILD) || empty(FETCH_BUILD))
# fetch-import-source-req: extracted (+patched) source becomes this
# module's own SRCS, compiled through the ordinary pipeline below --
# no _IMPORT_CFLAGS/_IMPORT_LIBS/_IMPORT_LIBDIR of its own (there is no
# prebuilt artifact to point at), only the resolved work-tree root.
# @impl 0f87-6ab6-4fe1-98d2
_IMPORT_FETCH_LABEL = ${IMPORT:C/^[^:]*://}
_IMPORT_SOURCE  = fetch:${_IMPORT_FETCH_LABEL}
_IMPORT_KIND    = source
_IMPORT_WRKSRC  = ${.CURDIR}/work/_resolved
.  elif ${IMPORT:C/:.*//} == "fetch"
# fetch-build-req: FETCH_BUILD= delegates the extracted (+patched)
# source to its OWN upstream build system (autotools/cmake/meson/
# custom) instead of SRCS=, installing into a module-local prefix
# (work/_install) -- then treated exactly like a fetch-bin: import for
# every purpose past this point (_IMPORT_CFLAGS/_IMPORT_LIBS/_IMPORT_LIBDIR
# point at that local prefix, staged via the SAME _stage_import: pkg:/
# prefix:/fetch-bin: already use). See 26-fetched-external-sources.md.
# @impl 0f87-6ab6-6562-0f89
_IMPORT_FETCH_LABEL = ${IMPORT:C/^[^:]*://}
_IMPORT_SOURCE  = fetch:${_IMPORT_FETCH_LABEL}
_IMPORT_KIND    = source-build
_IMPORT_WRKSRC  = ${.CURDIR}/work/_resolved
_FETCH_INSTALL_PREFIX = ${.CURDIR}/work/_install
_FETCH_BUILD_DIR = ${.CURDIR}/work/_build
_IMPORT_CFLAGS  = -I${_FETCH_INSTALL_PREFIX}/include
_IMPORT_LIBS    = -L${_FETCH_INSTALL_PREFIX}/lib -l${LIB}
_IMPORT_LIBDIR  = ${_FETCH_INSTALL_PREFIX}/lib
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
_IMPORT_LIBDIR  != ${_IMPORT_PC_ENV} pkg-config --variable=libdir ${_IMPORT_PKGNAME} 2>/dev/null
# shared-import-link-flags-fix-req: a shared library (.so/.dylib) embeds
# its own dependency references (install_name/rpath on macOS, DT_NEEDED
# on ELF), resolved by the dynamic linker at LOAD time, not link time --
# `--static`'s full transitive closure is both unnecessary for one and
# risky: a Requires.private entry may validly omit its own -L (relying
# on the HOST's own default linker search path, e.g. /opt/local/lib),
# which this project's own build doesn't necessarily share, producing
# `ld: library 'X' not found` for an entirely unrelated transitive
# dependency -- found in real use (gdal's own lz4 dependency). Only a
# STATIC-only import (no .so/.dylib found at the resolved libdir) needs
# the full --static closure (D2, import-link-transitivity-req), since a
# .a carries no dependency info of its own for the final consumer to
# resolve at link time.
# @impl 0f87-6abe-3ef3-cd79
.      if exists(${_IMPORT_LIBDIR}/lib${LIB}.so) || exists(${_IMPORT_LIBDIR}/lib${LIB}.dylib)
_IMPORT_LIBS    != ${_IMPORT_PC_ENV} pkg-config --libs ${_IMPORT_PKGNAME} 2>/dev/null
.      else
_IMPORT_LIBS    != ${_IMPORT_PC_ENV} pkg-config --libs --static ${_IMPORT_PKGNAME} 2>/dev/null
.      endif
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
# header-only-import-req: IMPORT_LIB=none switches the success criterion
# from "a lib file exists" to "the first IMPORT_HEADERS= entry exists
# under this prefix's include/" -- there is no lib file to probe for.
.  if !defined(_IMPORT_SOURCE)
.    for _p in ${_TOOL_PREFIXES:H:O:u}
.      if ${IMPORT_LIB} == "none"
.        if !defined(_IMPORT_SOURCE) && exists(${_p}/include/${IMPORT_HEADERS:[1]})
_IMPORT_SOURCE  = probe:${_p}
_IMPORT_CFLAGS  = -I${_p}/include
.        endif
.      elif !defined(_IMPORT_SOURCE) && (exists(${_p}/lib/lib${LIB}.a) || exists(${_p}/lib/lib${LIB}.so) || exists(${_p}/lib/lib${LIB}.dylib))
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

# header-only-import-req: whatever DID resolve (pkg:/prefix:/env/hook/
# probing), suppress lib-staging regardless of what it reported --
# _stage_import: already treats an empty _IMPORT_LIBDIR as "nothing to
# stage" (import-staging-req), so this reuses that path rather than
# adding a new one.
.  if ${IMPORT_LIB} == "none"
_IMPORT_LIBS    =
_IMPORT_LIBDIR  =
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
#
# noop-rebuild-fix-req: _FETCH_PREREQ names the REAL stamp file
# (work/.extract-fp), not the phony _fetch_import target itself --
# found empirically that listing a .PHONY target directly as a
# prerequisite of a real .o: rule forces bmake to treat that .o as
# stale on EVERY build, regardless of whether _fetch_import's own
# internal fingerprint decided nothing needed re-extracting (a .PHONY
# prerequisite has no mtime of its own, so make treats anything
# depending on one as unconditionally out of date -- confirmed by a
# fetch: module recompiling and re-archiving on a second, completely
# unchanged build). _fetch_import itself is still listed explicitly on
# all: below (ensuring it runs, and so work/.extract-fp gets created,
# before any .o: rule's own dependency chain is evaluated) -- but
# that's a prerequisite of the PHONY all:, which already runs its own
# recipe every time regardless, so no cascading harm there.
# @impl 0f87-6ab6-4fe1-98d2
# @impl 0f87-6abe-3f12-1050
.if ${_IMPORT_KIND:Uno} == "source"
_SRC_BASE = ${_IMPORT_WRKSRC}
_FETCH_PREREQ = ${.CURDIR}/work/.extract-fp
# fetch-root-include-req: the resolved work tree's own root is on the
# include search path, so a nested SRCS= entry (Dear ImGui's own
# backends/*.cpp, #include-ing "imgui.h" from the tree root) compiles
# without a hand-written mk/ hook -- found in real use: it only ever
# worked by accident, because an EARLIER build had already staged
# imgui.h into the framework's own public include dir, masking the gap
# on every incremental build after the first.
# @impl 0f87-6abe-3f03-19dd
CFLAGS   += -I${_IMPORT_WRKSRC}
CXXFLAGS += -I${_IMPORT_WRKSRC}
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

# nested-srcs-objdir-req: each compile rule below mkdir -p's its own
# ${.TARGET:H} (the object's own subdirectory, from a nested SRCS=
# entry like backends/foo.cpp) before invoking the compiler -- found
# empirically that a fetched module's own re-extraction (_fetch_import:'s
# rm -rf/mkdir -p ${_OBJDIR}) only recreates the TOP-LEVEL object dir,
# clearing a subdirectory an external hook had already created, so a
# multi-directory fetched source (Dear ImGui, with backend sources under
# backends/) failed to compile on a first build.
# @impl 0f87-6aba-a54a-f741
.for _s in ${SRCS}
.  if ${_s:E} == "c"
${_OBJDIR}/${_s:R}.o: ${_FETCH_PREREQ} ${_SRC_BASE}/${_s} ${_INPUTS_HASH_FILE}
	@mkdir -p ${.TARGET:H}
	${CC} ${CFLAGS} ${_DEP_CFLAGS} ${_DEP_CFLAGS:D-MF ${_OBJDIR}/${_s:R}.d} -fPIC -c ${_SRC_BASE}/${_s} -o ${.TARGET}
.  elif !empty(_CXX_EXTS:M${_s:E})
${_OBJDIR}/${_s:R}.o: ${_FETCH_PREREQ} ${_SRC_BASE}/${_s} ${_INPUTS_HASH_FILE}
	@mkdir -p ${.TARGET:H}
	${CXX} ${CXXFLAGS} ${_DEP_CFLAGS} ${_DEP_CFLAGS:D-MF ${_OBJDIR}/${_s:R}.d} -fPIC -c ${_SRC_BASE}/${_s} -o ${.TARGET}
.  elif ${_s:E} == "y"
${_OBJDIR}/${_s:R}.c: ${_FETCH_PREREQ} ${_SRC_BASE}/${_s}
	@mkdir -p ${.TARGET:H}
	${YACC} ${YFLAGS} -d -o ${.TARGET} ${_SRC_BASE}/${_s}
	@if [ -f y.tab.h ]; then mv y.tab.h ${_OBJDIR}/${_s:R}.h; fi
	@mkdir -p ${.CURDIR}/${INCDIR_LOCAL}
	@if [ -f ${_OBJDIR}/${_s:R}.h ]; then cp -f ${_OBJDIR}/${_s:R}.h ${.CURDIR}/${INCDIR_LOCAL}/; fi
${_OBJDIR}/${_s:R}.o: ${_OBJDIR}/${_s:R}.c ${_INPUTS_HASH_FILE}
	@mkdir -p ${.TARGET:H}
	${CC} ${CFLAGS} ${_DEP_CFLAGS} ${_DEP_CFLAGS:D-MF ${_OBJDIR}/${_s:R}.d} -fPIC -c ${_OBJDIR}/${_s:R}.c -o ${.TARGET}
.  elif ${_s:E} == "l"
${_OBJDIR}/${_s:R}.c: ${_FETCH_PREREQ} ${_SRC_BASE}/${_s}
	@mkdir -p ${.TARGET:H}
	${LEX} ${LFLAGS} -o ${.TARGET} ${_SRC_BASE}/${_s}
${_OBJDIR}/${_s:R}.o: ${_OBJDIR}/${_s:R}.c ${_INPUTS_HASH_FILE}
	@mkdir -p ${.TARGET:H}
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
# headers. noop-rebuild-fix-req: _fetch_import is listed explicitly
# here (not just via _FETCH_PREREQ on each .o: rule) so it's guaranteed
# to run -- and so work/.extract-fp exists -- before any .o:'s own
# dependency chain is evaluated; all: is itself .PHONY, so a phony
# prerequisite here costs nothing extra.
.  if ${LIB_SHARED} == "YES"
all: _check_inputs_hash _create_dirs _fetch_import ${_LIBOUT_DIR}/${SHLIB_NAME} _stage_fetch_headers _write_linkdeps
	@:
.  else
all: _check_inputs_hash _create_dirs _fetch_import ${_LIBOUT_DIR}/${STATIC_NAME} _stage_fetch_headers _write_linkdeps
	@:
.  endif
.elif ${_IMPORT_KIND:Uno} == "source-build"
# fetch-build-req: the extracted (+patched) source is built by its OWN
# upstream build system (_fetch_build:, after _fetch_import:) and
# installed into a module-local prefix, then staged exactly like a
# fetch-bin: import -- no SRCS=/OBJS=/compile step of Bmake It's own.
all: _check_inputs_hash _create_dirs _fetch_import _fetch_build _stage_import _write_linkdeps
	@:
.elif !empty(IMPORT)
all: _check_inputs_hash _create_dirs _fetch_import _stage_import _write_linkdeps
	@:
.elif ${LIB_SHARED} == "YES"
all: _check_inputs_hash _create_dirs ${_LIBOUT_DIR}/${SHLIB_NAME} _promote_incl _write_linkdeps
	@:
.else
all: _check_inputs_hash _create_dirs ${_LIBOUT_DIR}/${STATIC_NAME} _promote_incl _write_linkdeps
	@:
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
# transitive-linkdeps-missing-L-fix-req: the resolved -L<dir> (link
# time) AND -Wl,-rpath,<dir> (run time, shared libs only -- no rpath
# concept on Windows) travel alongside -l<name>, not just the bare name
# -- a .linkdeps consumer that doesn't *also* happen to put this
# library's own directory on its search path some other way (e.g. by
# listing the same framework in its own PREREQS=) would otherwise link
# only by accident, and even then dyld/ld.so still couldn't LOAD a
# shared lib found only this transitively (confirmed empirically:
# fixing just -L produces a binary that links but dyld can't find at
# run time). _LIB_FILE.${_l} is already resolved above for the
# relink-on-libs-change fix; its own dirname is exactly this directory.
# @impl 0f87-6abe-3f27-cde6
.    if !empty(_LIB_FILE.${_l})
_OWN_LINKDEPS += -L${_LIB_FILE.${_l}:H}
.      if ${TARGET} != "win"
_OWN_LINKDEPS += -Wl,-rpath,${_LIB_FILE.${_l}:H}
.      endif
.    endif
_OWN_LINKDEPS += -l${_l}
.    for _d in ${_LIB_SEARCH_DIRS}
.      if exists(${_d}/lib${_l}.linkdeps)
_OWN_LINKDEPS += ${_LINKDEPS.${_l}}
.      endif
.    endfor
.  endfor
.endif

# repeated-messages-fix-req: "built ..." is printed by the recipe that
# actually archives/links (not by all:, which runs on every visit), so a
# visit that rebuilt nothing says nothing.
.if ${_IMPORT_KIND:Uno} == "source"
_BUILT_NOTE = (fetched: ${_IMPORT_SOURCE})
.else
_BUILT_NOTE =
.endif

# linkdeps-write-idempotent-req: _write_linkdeps is .PHONY (runs on every
# all: evaluation), so an unconditional write bumped the file's mtime on
# every visit and fed every downstream copy-up pass. Write only when the
# computed content differs from what is already on disk.
# @impl 0f87-6abe-8e68-fc89
_write_linkdeps:
	@_new="${_OWN_LINKDEPS}"; \
	if [ -f ${_LIBOUT_DIR}/lib${LIB}.linkdeps ] && [ "$$(cat ${_LIBOUT_DIR}/lib${LIB}.linkdeps)" = "$$_new" ]; then \
		exit 0; \
	fi; \
	echo "$$_new" > ${_LIBOUT_DIR}/lib${LIB}.linkdeps

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
# import-staging-idempotent-req: one shell block, guarded by a
# fingerprint of everything that determines WHAT gets staged (IMPORT=,
# IMPORT_HEADERS=, IMPORT_LIB=, and the resolved source/cflags/libdir),
# stored in ${BUILD_ROOT}/.stage-fp (under the build root so `bmake clean` discards it together with the staged outputs it vouches for) -- same idiom _fetch_import: already uses.
# _stage_import is .PHONY and listed directly under all:, so it was
# re-running its whole body (re-copying every header and lib, re-printing
# "imported"/"staged header(s)") on every all: evaluation -- up to 4
# times per build for one imported module (workspace all+copy-up x
# framework all+copy-up). An unchanged fingerprint now exits silently
# before any copy or print. The IMPORT_HEADERS= loop is a shell `for`,
# not a bmake .for, precisely so the whole body is ONE script and the
# early exit actually skips everything (each .for iteration would be its
# own recipe line, which an `exit 0` could not short-circuit).
# import-headers-glob-req: an entry containing a shell glob
# metacharacter (*, ?, [...]) stages every match, not just one exact
# name/directory -- found in real use (GDAL installs ~150 loose headers
# directly in its includedir, no per-package subdirectory to stage
# wholesale the way IMPORT_HEADERS= already could; a real project had
# to hand-list the 49 it actually used). A plain, glob-free entry
# behaves exactly as before: the shell's own glob expansion leaves a
# non-matching literal pattern untouched, so `[ -e ... ]` on it
# correctly reports "not found" the same way it always has.
# @impl 0f87-6abe-3f41-3d0f
# @impl 0f87-6abe-8e68-741b
_stage_import:
	@mkdir -p ${_FWDIR}/${BUILD_ROOT}/include ${_LIBOUT_DIR}; \
	_fp=$$(printf '%s' "IMPORT=${IMPORT} HEADERS=${IMPORT_HEADERS} LIB=${IMPORT_LIB} SRC=${_IMPORT_SOURCE} CFLAGS=${_IMPORT_CFLAGS} LIBDIR=${_IMPORT_LIBDIR}" | cksum); \
	if [ -f ${.CURDIR}/${BUILD_ROOT}/.stage-fp ] && [ "$$(cat ${.CURDIR}/${BUILD_ROOT}/.stage-fp)" = "$$_fp" ]; then \
		exit 0; \
	fi; \
	echo "===> IMPORT=${IMPORT}: resolved via ${_IMPORT_SOURCE}"; \
	for _h in ${IMPORT_HEADERS}; do \
		_found=no; \
		for _d in ${_IMPORT_CFLAGS:M-I*:S/-I//}; do \
			_matched=no; \
			for _f in "$$_d"/$$_h; do \
				if [ -e "$$_f" ]; then \
					cp -a "$$_f" ${_FWDIR}/${BUILD_ROOT}/include/; \
					_matched=yes; \
				fi; \
			done; \
			if [ "$$_matched" = yes ]; then \
				echo "===> staged header(s) $$_h from $$_d"; \
				_found=yes; \
				break; \
			fi; \
		done; \
		if [ "$$_found" = no ]; then \
			echo "error: IMPORT_HEADERS=$$_h: not found under any resolved include dir (${_IMPORT_CFLAGS})" >&2; \
			exit 1; \
		fi; \
	done; \
	if [ -z "${_IMPORT_LIBDIR}" ]; then \
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
	fi; \
	echo "$$_fp" > ${.CURDIR}/${BUILD_ROOT}/.stage-fp; \
	echo "===> imported ${LIB} (${_IMPORT_SOURCE})"

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
.if ${_IMPORT_KIND:Uno} != "source" && ${_IMPORT_KIND:Uno} != "binary" && ${_IMPORT_KIND:Uno} != "source-build"
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

# fetch-build-req: when FETCH_BUILD= is set on an IMPORT=fetch: module,
# the extracted (+patched) source (_fetch_import: already ran as an
# earlier prerequisite) is built with its OWN upstream build system
# instead of Bmake It's SRCS= pipeline -- a hand-picked source list
# can't cope with a real autotools/CMake/Meson project. Named presets
# run a sensible default recipe into a module-local prefix
# (work/_install, via a scratch work/_build build directory for the
# out-of-tree cmake/meson presets); FETCH_BUILD=custom runs
# FETCH_BUILD_CMD= verbatim for anything else, with the source dir/
# build dir/install prefix exported as BMK_FETCH_SRCDIR/
# BMK_FETCH_BUILD_DIR/BMK_FETCH_INSTALL_PREFIX. Bmake It's own CC/CXX/
# CFLAGS/CXXFLAGS/LDFLAGS are forwarded as environment variables, so the
# upstream build uses the SAME compiler Bmake It is building with --
# correct for a native build under any preset; correct for a CROSS
# build only under autotools (CC/CXX already carry clang's --target=/
# --sysroot=, and --host=<triple> is derived from the same
# mk.toolchain.llvm.mk _CROSS_FLAGS) -- CMake's -DCMAKE_C_COMPILER=/
# Meson's compiler detection both want a bare executable path, so a
# cross build under FETCH_BUILD=cmake/meson silently loses the cross
# flags rather than erroring; a CMAKE_TOOLCHAIN_FILE/Meson cross-file
# generator is deferred, not implemented (26-fetched-external-sources.md).
# Cached via a fingerprint (work/.build-fp) over FETCH_BUILD=/
# FETCH_BUILD_ARGS=/FETCH_BUILD_CMD=/CC/CXX/CFLAGS/CXXFLAGS AND the
# extraction fingerprint itself, so a source or toolchain change forces
# a real rebuild but nothing else does -- upstream configure+build+
# install can be genuinely slow. Every -I/-L/-Wl,-rpath, path in CFLAGS/
# CXXFLAGS is realpath-normalized before hashing: confirmed (empirically)
# that a bare .CURDIR-derived path can be textually /var/folders/... in
# one bmake invocation and /private/var/folders/... (same real directory
# -- macOS's /tmp and /var are themselves symlinks into /private) in
# another, which otherwise made this fingerprint flap between two
# different values across the SAME unchanged build under a tmpdir-based
# test harness, defeating the cache. MAKEFLAGS/MAKELEVEL/MFLAGS/MAKE are
# unset before delegating -- inherited from the OUTER bmake process
# otherwise, and confirmed (empirically) to silently break CMake's own
# internal make/ninja invocation: `cmake --build` ran, printed nothing,
# and produced no build output at all, exactly the class of bug this
# project's own run-tests.sh harness already clears these same
# variables for when launching a nested bmake.
#
# fetch-build-forwarding-fix-req: this module's own fully-assembled
# LDFLAGS (accumulating -L/-l/-Wl,-rpath, entries for linking against
# SIBLING frameworks/prereqs -- meaningless, and found empirically
# actively harmful, to an INDEPENDENT upstream build) is never
# forwarded; only _TOOLCHAIN_LDFLAGS (a snapshot taken before any of
# that, right after mk.common.mk's own SANITIZE=/OPENMP= contributions)
# is. CMAKE_PREFIX_PATH (a sibling FETCH_BUILD= module's own install
# prefix, so find_package() can see it) and, on macOS,
# MACOSX_DEPLOYMENT_TARGET (so a fetched library never silently picks a
# different minimum OS version than this project's own native objects,
# which caused linker warnings) are also forwarded now.
# @impl 0f87-6ab6-6562-0f89
_fetch_build:
.if ${_IMPORT_KIND:Uno} != "source-build"
	@:
.else
	@_ct="${_CROSS_FLAGS:U:M--target=*:C/--target=//}"; \
	_normflags() { \
		_out=""; \
		for _t in $$1; do \
			case "$$_t" in \
				-I/*|-L/*) \
					_p=$${_t#-?}; \
					_r=$$(realpath "$$_p" 2>/dev/null || printf '%s' "$$_p"); \
					_out="$$_out $${_t%%/*}$$_r" ;; \
				-Wl,-rpath,/*) \
					_p=$${_t#-Wl,-rpath,}; \
					_r=$$(realpath "$$_p" 2>/dev/null || printf '%s' "$$_p"); \
					_out="$$_out -Wl,-rpath,$$_r" ;; \
				*) _out="$$_out $$_t" ;; \
			esac; \
		done; \
		printf '%s' "$$_out"; \
	}; \
	_ncflags=$$(_normflags "${CFLAGS}"); \
	_ncxxflags=$$(_normflags "${CXXFLAGS}"); \
	_ntoolchainldflags=$$(_normflags "${_TOOLCHAIN_LDFLAGS}"); \
	_npfxpath=""; \
	for _pp in ${_FETCH_CMAKE_PREFIX_PATH:S/;/ /g}; do \
		_npfxpath="$$_npfxpath$$(realpath "$$_pp" 2>/dev/null || printf '%s' "$$_pp");"; \
	done; \
	_bfp=$$(printf '%s' "BUILD=${FETCH_BUILD} ARGS=${FETCH_BUILD_ARGS} CMD=${FETCH_BUILD_CMD} CC=${CC} CXX=${CXX} CFLAGS=$$_ncflags CXXFLAGS=$$_ncxxflags LDFLAGS=$$_ntoolchainldflags PREFIXPATH=$$_npfxpath DEPLOY=${_FETCH_MACOS_MIN_VERSION:U} EXTRACT=$$(cat ${.CURDIR}/work/.extract-fp 2>/dev/null)" | cksum); \
	if [ -f ${.CURDIR}/work/.build-fp ] && [ "$$(cat ${.CURDIR}/work/.build-fp)" = "$$_bfp" ]; then \
		exit 0; \
	fi; \
	_prefix=${_FETCH_INSTALL_PREFIX}; \
	_builddir=${_FETCH_BUILD_DIR}; \
	rm -rf "$$_prefix" "$$_builddir"; \
	mkdir -p "$$_prefix" "$$_builddir"; \
	_njobs=$$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1); \
	unset MAKEFLAGS MAKELEVEL MFLAGS MAKE 2>/dev/null || true; \
	export CC="${CC}" CXX="${CXX}" CFLAGS="${CFLAGS}" CXXFLAGS="${CXXFLAGS}" LDFLAGS="${_TOOLCHAIN_LDFLAGS}"; \
	export CMAKE_PREFIX_PATH="${_FETCH_CMAKE_PREFIX_PATH}"; \
	_pcpath=""; \
	for _pp in ${_FETCH_CMAKE_PREFIX_PATH:S/;/ /g}; do _pcpath="$$_pcpath$$_pp/lib/pkgconfig:"; done; \
	[ -n "$$_pcpath" ] && export PKG_CONFIG_PATH="$$_pcpath$${PKG_CONFIG_PATH:-}"; \
	${_FETCH_DEPLOY_EXPORT} \
	case "${FETCH_BUILD}" in \
		autotools) \
			echo "===> FETCH_BUILD=autotools: configure && make && make install"; \
			_host=""; \
			[ -n "$$_ct" ] && _host="--host=$$_ct"; \
			( cd ${_IMPORT_WRKSRC} && \
			  ./configure --prefix="$$_prefix" $$_host ${FETCH_BUILD_ARGS} && \
			  make -j"$$_njobs" && \
			  make install ) || { echo "error: IMPORT=${IMPORT}: autotools build failed" >&2; exit 1; }; \
			;; \
		cmake) \
			command -v cmake >/dev/null 2>&1 || { echo "error: IMPORT=${IMPORT}: FETCH_BUILD=cmake but cmake not found on PATH" >&2; exit 1; }; \
			echo "===> FETCH_BUILD=cmake: configure && build && install"; \
			( cmake -S ${_IMPORT_WRKSRC} -B "$$_builddir" -DCMAKE_INSTALL_PREFIX="$$_prefix" \
				-DCMAKE_C_COMPILER="${CC:[1]}" -DCMAKE_CXX_COMPILER="${CXX:[1]}" \
				-DCMAKE_PREFIX_PATH="${_FETCH_CMAKE_PREFIX_PATH}" \
				${FETCH_BUILD_ARGS} && \
			  cmake --build "$$_builddir" -j"$$_njobs" && \
			  cmake --install "$$_builddir" ) || { echo "error: IMPORT=${IMPORT}: cmake build failed" >&2; exit 1; }; \
			;; \
		meson) \
			command -v meson >/dev/null 2>&1 || { echo "error: IMPORT=${IMPORT}: FETCH_BUILD=meson but meson not found on PATH" >&2; exit 1; }; \
			echo "===> FETCH_BUILD=meson: setup && compile && install"; \
			( meson setup "$$_builddir" ${_IMPORT_WRKSRC} --prefix="$$_prefix" ${FETCH_BUILD_ARGS} && \
			  meson compile -C "$$_builddir" && \
			  meson install -C "$$_builddir" ) || { echo "error: IMPORT=${IMPORT}: meson build failed" >&2; exit 1; }; \
			;; \
		custom) \
			if [ -z "${FETCH_BUILD_CMD}" ]; then \
				echo "error: IMPORT=${IMPORT}: FETCH_BUILD=custom requires FETCH_BUILD_CMD=" >&2; exit 1; \
			fi; \
			echo "===> FETCH_BUILD=custom: ${FETCH_BUILD_CMD}"; \
			( cd ${_IMPORT_WRKSRC} && \
			  BMK_FETCH_SRCDIR=${_IMPORT_WRKSRC} BMK_FETCH_BUILD_DIR="$$_builddir" BMK_FETCH_INSTALL_PREFIX="$$_prefix" \
			  sh -c '${FETCH_BUILD_CMD}' ) || { echo "error: IMPORT=${IMPORT}: FETCH_BUILD_CMD failed" >&2; exit 1; }; \
			;; \
		*) \
			echo "error: IMPORT=${IMPORT}: unknown FETCH_BUILD=${FETCH_BUILD} (expected autotools, cmake, meson, or custom)" >&2; \
			exit 1; \
			;; \
	esac; \
	echo "$$_bfp" > ${.CURDIR}/work/.build-fp; \
	echo "===> built via FETCH_BUILD=${FETCH_BUILD}, installed to $$_prefix"
.endif

# fetch-import-source-req: header staging for the SOURCE kind, reusing
# IMPORT_HEADERS= and the SAME search-and-copy shell logic _stage_import:
# already uses -- just against the fetched work tree instead of a
# resolved prefix, and without the lib${LIB}.* half (compiling produces
# that, via the ordinary ${_LIBOUT_DIR}/${SHLIB_NAME}/${STATIC_NAME}
# recipes below).
# @impl 0f87-6ab6-4fe1-98d2
# repeated-messages-fix-req: fingerprint-guarded like _stage_import: --
# IMPORT_HEADERS= plus the extraction fingerprint (work/.extract-fp), kept
# under the build root. Unchanged => silent, nothing re-copied.
# @impl 0f87-6abf-aeba-e6a2
_stage_fetch_headers:
.if !empty(IMPORT_HEADERS)
	@mkdir -p ${_FWDIR}/${BUILD_ROOT}/include ${.CURDIR}/${BUILD_ROOT}; \
	_fp=$$(printf '%s' "HEADERS=${IMPORT_HEADERS} WRK=${_IMPORT_WRKSRC} EXTRACT=$$(cat ${.CURDIR}/work/.extract-fp 2>/dev/null)" | cksum); \
	if [ -f ${.CURDIR}/${BUILD_ROOT}/.stage-fetch-fp ] && [ "$$(cat ${.CURDIR}/${BUILD_ROOT}/.stage-fetch-fp)" = "$$_fp" ]; then \
		exit 0; \
	fi; \
	for _h in ${IMPORT_HEADERS}; do \
		_found=no; \
		for _d in ${_IMPORT_WRKSRC} ${_IMPORT_WRKSRC}/include; do \
			if [ -e "$$_d/$$_h" ]; then \
				cp -a "$$_d/$$_h" ${_FWDIR}/${BUILD_ROOT}/include/; \
				echo "===> staged header $$_h from $$_d"; \
				_found=yes; \
				break; \
			fi; \
		done; \
		if [ "$$_found" = no ]; then \
			echo "error: IMPORT_HEADERS=$$_h: not found under the fetched work tree (${_IMPORT_WRKSRC} or its include/)" >&2; \
			exit 1; \
		fi; \
	done; \
	echo "$$_fp" > ${.CURDIR}/${BUILD_ROOT}/.stage-fetch-fp
.endif

# @impl 0f87-6a98-8b7f-9215
${_LIBOUT_DIR}/${SHLIB_NAME}: ${OBJS} ${_LIBS_FILES}
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
# duplicate-linkdeps-fix-req/ldflags-dedup-hook-timing-fix-req: see
# mk.prog.mk's identical comment -- computed in the recipe (sees
# LDFLAGS after every hook phase, unlike a top-level != assignment),
# restricted to -l*/-L*/-Wl,-rpath,* so a flag+argument pair (e.g.
# -framework X) is never split.
# @impl 0f87-6abe-3f50-0560
# @impl 0f87-6abe-8c3c-9ca3
	@_ldflags=""; _seen=""; \
	for _f in ${LDFLAGS}; do \
		_skip=no; \
		case "$$_f" in \
			-l*|-L*|-Wl,-rpath,*) \
				case " $$_seen " in \
					*" $$_f "*) _skip=yes ;; \
				esac; \
				[ "$$_skip" = no ] && _seen="$$_seen $$_f" ;; \
		esac; \
		[ "$$_skip" = no ] && _ldflags="$$_ldflags $$_f"; \
	done; \
	echo "${_CCLINK} ${_SHLIB_LDFLAGS} -o ${.TARGET} ${OBJS} $$_ldflags"; \
	${_CCLINK} ${_SHLIB_LDFLAGS} -o ${.TARGET} ${OBJS} $$_ldflags
	@echo "===> built shared ${SHLIB_NAME}${_BUILT_NOTE:C/^(.)/ \1/}"
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
	@echo "===> built static ${STATIC_NAME}${_BUILT_NOTE:C/^(.)/ \1/}"

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

.PHONY: all clean help copy-up _create_dirs _promote_incl _stage_import _fetch_import _fetch_build _stage_fetch_headers _write_linkdeps help
.endif

