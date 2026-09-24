# mk.common.mk — shared definitions for Bmake It
# Included by workspace / framework / prog / lib roles.

.if !defined(_MK_COMMON_MK_)
_MK_COMMON_MK_ = 1

# ---------------------------------------------------------------------------
# Host detection → default TARGET / TARGET_ARCH / TOOLCHAIN
# ---------------------------------------------------------------------------
# Computed unconditionally (not just when TARGET is unset): the host OS is
# also what selects mk.paths.<os>.mk below, for locating the HOST-native
# compiler when not cross-compiling -- that's needed even when TARGET was
# explicitly given (e.g. TARGET=freebsd for cross, or TARGET=all for clean).
_HOST_OS != uname -s | tr '[:upper:]' '[:lower:]'
_HOST_ARCH != uname -m

# Host OS/arch normalized to this project's own labels -- computed
# unconditionally (not just as a TARGET/TARGET_ARCH default) because cross
# compilation detection below needs to compare the REQUESTED target against
# what the host actually is, regardless of whether TARGET was defaulted or
# explicitly given.
.if ${_HOST_OS} == "darwin"
_HOST_OS_LABEL = macos
.elif ${_HOST_OS} == "freebsd"
_HOST_OS_LABEL = freebsd
.elif ${_HOST_OS} == "linux"
_HOST_OS_LABEL = linux
# Cygwin's own `uname -s` is not a clean "cygwin" -- it's version-suffixed
# (e.g. "CYGWIN_NT-10.0-19045", varies by Windows build), so it can never
# be matched with a plain ==. Glob-match the prefix instead.
# @impl 0f87-6a98-96de-1355
.elif ${_HOST_OS:Mcygwin*}
_HOST_OS_LABEL = win
.else
_HOST_OS_LABEL = ${_HOST_OS}
.endif

.if ${_HOST_ARCH} == "x86_64" || ${_HOST_ARCH} == "amd64"
_HOST_ARCH_LABEL = amd64
.elif ${_HOST_ARCH} == "aarch64" || ${_HOST_ARCH} == "arm64"
_HOST_ARCH_LABEL = arm64
.else
_HOST_ARCH_LABEL = ${_HOST_ARCH}
.endif

.if !defined(TARGET) || empty(TARGET)
TARGET = ${_HOST_OS_LABEL}
.endif

.if !defined(TARGET_ARCH) || empty(TARGET_ARCH)
TARGET_ARCH = ${_HOST_ARCH_LABEL}
.endif

.if !defined(TOOLCHAIN) || empty(TOOLCHAIN)
TOOLCHAIN = llvm
.endif

# Are we actually cross-compiling? (REQ-target-arch-toolchain-selection-is-custom-req)
.if ${TARGET} == ${_HOST_OS_LABEL} && ${TARGET_ARCH} == ${_HOST_ARCH_LABEL}
BMK_IS_NATIVE_BUILD = yes
.else
BMK_IS_NATIVE_BUILD = no
.endif

# ---------------------------------------------------------------------------
# Target key  (REQ-target-key-omit-defaults-req)
# <os>-<arch>[-<toolchain>][-<abi>]
# Defaults omitted: toolchain=llvm, abi = platform default (glibc on linux)
# ---------------------------------------------------------------------------
_TARGET_KEY := ${TARGET}-${TARGET_ARCH}
.if ${TOOLCHAIN} != "llvm"
_TARGET_KEY := ${_TARGET_KEY}-${TOOLCHAIN}
.endif
# @impl 0f87-6a98-772e-6156
.if defined(ABI) && !empty(ABI)
.  if ${TARGET} == "linux" && ${ABI} != "glibc"
_TARGET_KEY := ${_TARGET_KEY}-${ABI}
.  elif ${TARGET} == "win" && ${ABI} != "msvc"
_TARGET_KEY := ${_TARGET_KEY}-${ABI}
.  endif
.endif
OS_ARCH := ${_TARGET_KEY}

# ---------------------------------------------------------------------------
# Build / distrib roots
# ---------------------------------------------------------------------------
BUILD_ROOT   = build/${OS_ARCH}
DISTRIB_ROOT = distrib/${OS_ARCH}

# ---------------------------------------------------------------------------
# clean scope (REQ-clean-removes-all-derived-artifacts-req / target-selection
# semantics unchanged from clean-target-scope-req): plain `clean` touches only
# the current/selected target's build/<KEY>/ and distrib/<KEY>/; the special
# value TARGET=all wipes every target's output at once.
# ---------------------------------------------------------------------------
.if ${TARGET} == "all"
CLEAN_ALL_TARGETS = yes
.else
CLEAN_ALL_TARGETS = no
.endif

# Relative to current makefile's directory
OBJDIR   = ${BUILD_ROOT}/obj
BINDIR_LOCAL = ${BUILD_ROOT}/bin
LIBDIR_LOCAL = ${BUILD_ROOT}/lib
INCDIR_LOCAL = ${BUILD_ROOT}/include
SHAREDIR_LOCAL = ${BUILD_ROOT}/share

# bmk_export.h (portable dllexport/dllimport macro, REQ-msvc-shared-lib-export-req)
# lives alongside mk/ in the project root -- put it on every module's
# include path unconditionally, not just when TARGET=win, since it's a
# harmless no-op include on every other platform too.
CFLAGS   += -I${BMK_MKDIR}/../include
CXXFLAGS += -I${BMK_MKDIR}/../include

# ---------------------------------------------------------------------------
# Host tool-search prefixes (REQ-toolchain-mk-must-set-explicit-cc-paths-req-v5)
# One mk.paths.<os>.mk per host OS, declaring where that platform's package
# manager(s) actually put compilers -- e.g. pkgsrc on NetBSD lands in
# /usr/pkg/bin, not /usr/bin. mk.toolchain.*.mk consume _TOOL_PREFIXES
# instead of guessing a single shared list for every OS.
# ---------------------------------------------------------------------------
.if exists(${BMK_MKDIR}/mk.paths.${_HOST_OS}.mk)
.  include "${BMK_MKDIR}/mk.paths.${_HOST_OS}.mk"
.else
.  include "${BMK_MKDIR}/mk.paths.default.mk"
.endif

# ---------------------------------------------------------------------------
# Toolchain selection (REQ-toolchain-triggers-dedicated-mk-file-req)
# ---------------------------------------------------------------------------
.if exists(${BMK_MKDIR}/mk.toolchain.${TOOLCHAIN}.mk)
.  include "${BMK_MKDIR}/mk.toolchain.${TOOLCHAIN}.mk"
.elif exists(${.CURDIR}/../mk/mk.toolchain.${TOOLCHAIN}.mk)
.  include "${.CURDIR}/../mk/mk.toolchain.${TOOLCHAIN}.mk"
.else
# Fallback: try relative to this file
.  include "mk.toolchain.${TOOLCHAIN}.mk"
.endif

# ---------------------------------------------------------------------------
# Common flags reuse (REQ-flags-reuse-bsd-native-vars-req-v2)
# ---------------------------------------------------------------------------
# @impl 0f87-6a98-5ff4-5d24
CFLAGS   += ${DEBUG_FLAGS}
CXXFLAGS += ${DEBUG_FLAGS}

# ---------------------------------------------------------------------------
# C++ source extensions (cxx-link-driver-selection-req) -- the single shared
# list mk.prog.mk/mk.lib.mk use both to dispatch a source file to ${CXX} at
# compile time and to decide whether a module's final link needs ${CXX}
# instead of ${CC} (mk.common.mk's own _CCLINK, computed per-role after SRCS
# is known). Deliberately NOT sys.mk's own CXX_SUFFIXES (.C .cc .cpp .cxx,
# free on every bmake invocation with zero .include) -- reusing it would
# silently widen SRCS auto-discovery to a fourth extension (.C) neither
# mk.prog.mk's nor mk.lib.mk's `find src ...` looks for today.
# @impl 0f87-6ab5-7f76-0dcf
# ---------------------------------------------------------------------------
_CXX_EXTS = cc cpp cxx

# ---------------------------------------------------------------------------
# REPORT= uniform report/dashboard trigger (report-flag-uniform-trigger,
# build-workspace-aggregation-req, test-workspace-aggregation-req)
# One flag for build, test, and sanitizing-test runs alike -- not a
# separate target name per action. Purely about the dashboard: REPORT=yes
# additionally generates the workspace-level dashboard (build-report/ or
# test-report/) from the logs/results any run -- reported or not --
# already leaves behind; REPORT unset just skips that step. See
# FAIL_FAST= below for whether a failure stops the run.
# ---------------------------------------------------------------------------
REPORT ?= no

# ---------------------------------------------------------------------------
# FAIL_FAST= whether one module's failure stops a workspace/framework
# `all`/`test` run. Default (unset/no): a build or test failure in one
# module does NOT prevent every other module from still being built/
# tested -- the failure is recorded (build.failed marker; test's own
# non-zero exit) and the run continues, matching how `test` already
# behaved before REPORT= existed. FAIL_FAST=yes opts into the traditional
# stop-immediately-on-first-failure behavior instead, for a quick dev
# loop where seeing every other module's result isn't useful. Orthogonal
# to REPORT=: whether the run continues past a failure and whether a
# dashboard gets built from what happened are two independent questions.
# A bare single-module `bmake all`/`test` (not via workspace/framework
# recursion) is unaffected either way -- there's nothing else to continue
# past.
# ---------------------------------------------------------------------------
FAIL_FAST ?= no

# ---------------------------------------------------------------------------
# RUN_ID= identifies one run's logs/reports so re-running the same
# arch-toolchain target doesn't silently overwrite the previous run's
# build.log/test-results.xml/dashboards (run-history-not-overwritten-req).
# Default: timestamp + PID (collision-safe across near-simultaneous runs
# without needing a GNU-only `date` extension like %N, which macOS/BSD
# date doesn't have). Overridable so an external CI can pass its own
# build number or commit SHA instead -- Bmake It itself stays VCS-blind
# (ci-integration-scope-boundary). Computed once and forwarded through
# the same recursive calls as SANITIZE=/REPORT=/FAIL_FAST=, so every
# module/framework touched by one run shares the same RUN_ID.
# @impl 0f87-6aaa-72d2-8ffc
# ---------------------------------------------------------------------------
.if !defined(RUN_ID) || empty(RUN_ID)
RUN_ID != date +%Y%m%d-%H%M%S-$$$$ 2>/dev/null
.endif

# ---------------------------------------------------------------------------
# SANITIZE= sanitizer instrumentation (sanitizer-support-req)
# A plain compile/link-flag concern, not test-specific -- CFLAGS/CXXFLAGS/
# LDFLAGS are shared by every role that .includes this file, so this
# composes with `run` and `test` automatically. gcc/clang take a single
# -fsanitize=a,b flag directly; MSVC only supports AddressSanitizer,
# translated by msvc-cc-wrapper.sh (which forwards the gcc-style spelling
# to cl.exe as /fsanitize=address). mingw/Cygwin gcc support is real but
# patchy per-sanitizer -- not blocked here, just not guaranteed.
# ---------------------------------------------------------------------------
SANITIZE ?=
# @impl 0f87-6aaa-4155-c8fd
.if !empty(SANITIZE)
_SANITIZE_WORDS = ${SANITIZE:S/,/ /g}

# address/thread/memory instrument the runtime in mutually incompatible
# ways -- at most one of the three. undefined and leak compose with any
# of them (leak is folded into address by default on Linux/macOS, but a
# bare SANITIZE=leak is also valid standalone).
.  if !empty(_SANITIZE_WORDS:Maddress) && !empty(_SANITIZE_WORDS:Mthread)
.    error "SANITIZE=${SANITIZE}: address and thread sanitizers are mutually exclusive"
.  endif
.  if !empty(_SANITIZE_WORDS:Maddress) && !empty(_SANITIZE_WORDS:Mmemory)
.    error "SANITIZE=${SANITIZE}: address and memory sanitizers are mutually exclusive"
.  endif
.  if !empty(_SANITIZE_WORDS:Mthread) && !empty(_SANITIZE_WORDS:Mmemory)
.    error "SANITIZE=${SANITIZE}: thread and memory sanitizers are mutually exclusive"
.  endif

.  if ${TOOLCHAIN} == "msvc"
.    for _s in ${_SANITIZE_WORDS}
.      if ${_s} != "address"
.        error "SANITIZE=${_s}: MSVC only supports AddressSanitizer (SANITIZE=address) -- see docs/spec/40-cli-reference.md for toolchain limits"
.      endif
.    endfor
.  endif

CFLAGS   += -fsanitize=${SANITIZE}
CXXFLAGS += -fsanitize=${SANITIZE}
LDFLAGS  += -fsanitize=${SANITIZE}
.  if ${TOOLCHAIN} != "msvc"
# Preserve frame pointers for readable sanitizer stack traces -- standard
# companion flag, no-op cost-wise compared to what instrumentation already
# costs. Not applicable to the MSVC line (cl.exe has no equivalent switch
# the wrapper would need to translate).
CFLAGS   += -fno-omit-frame-pointer
CXXFLAGS += -fno-omit-frame-pointer
.  endif

# UndefinedBehaviorSanitizer's default is to log a diagnostic and KEEP
# RUNNING, not abort -- found empirically: a deliberate signed-integer-
# overflow test case still reported "passed" under SANITIZE=undefined,
# the diagnostic sitting unnoticed in stderr. That defeats the entire
# point of a sanitizer-catch test (or `run`/`test` failing loudly on a
# real bug), so make every undefined-behavior check fatal on first hit,
# matching how AddressSanitizer already aborts by default. Not an MSVC
# concern -- MSVC's /fsanitize=address has no UBSan-equivalent switch.
.  if !empty(_SANITIZE_WORDS:Mundefined) && ${TOOLCHAIN} != "msvc"
CFLAGS   += -fno-sanitize-recover=undefined
CXXFLAGS += -fno-sanitize-recover=undefined
.  endif
.endif

# Suppress man pages by default (project is userland tools/libs)
MAN =

# Every role file defines `all:` as its conceptual default target, but
# common.mk is .include'd before any role-specific target is parsed -- and
# bmake's default goal is simply the first target encountered unless told
# otherwise. Without this, the run: target below (also defined here) would
# silently become the default goal for a bare `bmake` invocation.
.MAIN: all

# ---------------------------------------------------------------------------
# run: convenience target (REQ-run-target-req / REQ-run-target-any-workspace-dir-req)
# Defined here (not in mk.workspace.mk) so it is reachable from a bmake
# invoked in ANY role's directory -- framework, module, or workspace itself --
# per the correction that `run` is conceptually workspace-level but should
# work from anywhere inside the workspace tree. The recipe walks up from
# .CURDIR looking for the nearest ancestor makefile that pulls in
# mk.workspace.mk, then re-execs `make run` there so PROGRAM=/ARGS= are
# resolved against the workspace's own BINDIR_LOCAL/LIBDIR_LOCAL (where
# copy-up already aggregated every framework's outputs).
# ---------------------------------------------------------------------------
.if ${TARGET} == "macos"
_RUN_LDPATH_VAR = DYLD_LIBRARY_PATH
.elif ${TARGET} == "win"
_RUN_LDPATH_VAR = PATH
.else
_RUN_LDPATH_VAR = LD_LIBRARY_PATH
.endif

# @impl 0f87-6a98-7946-1d85
run:
.if !defined(PROGRAM) || empty(PROGRAM)
	@echo "usage: make run PROGRAM=<name> [ARGS=<args>]" >&2; exit 1
.endif
	@_d=${.CURDIR}; \
	while [ ! -f "$$_d/makefile" ] || ! grep -q 'mk\.workspace\.mk' "$$_d/makefile" 2>/dev/null; do \
		_parent=$$(dirname "$$_d"); \
		if [ "$$_parent" = "$$_d" ]; then \
			echo "error: could not locate a workspace root above ${.CURDIR}" >&2; exit 1; \
		fi; \
		_d=$$_parent; \
	done; \
	if [ "$$_d" != "${.CURDIR}" ]; then \
		exec ${MAKE} -C "$$_d" run PROGRAM=${PROGRAM} ARGS="${ARGS}" \
			TARGET=${TARGET} TARGET_ARCH=${TARGET_ARCH} TOOLCHAIN=${TOOLCHAIN} \
			BMK_MKDIR=${BMK_MKDIR}; \
	fi; \
	_BIN=$$_d/${BINDIR_LOCAL}/${PROGRAM}; \
	if [ ! -x "$$_BIN" ]; then \
		echo "error: $$_BIN does not exist — build first" >&2; exit 1; \
	fi; \
	_LIBDIR=$$_d/${LIBDIR_LOCAL}; \
	env ${_RUN_LDPATH_VAR}="$$_LIBDIR:$$${_RUN_LDPATH_VAR}" "$$_BIN" ${ARGS}

.PHONY: run

.endif # _MK_COMMON_MK_
