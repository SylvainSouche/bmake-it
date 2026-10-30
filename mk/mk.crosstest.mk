# mk.crosstest.mk -- where `bmake test` runs the tests (cross-test-runner-dec).
#
# Included by mk.test.mk and mk.tst.mk. The tests run
#   locally   unless the target is foreign to the build host (a different OS or
#             architecture) and no runner is named, or TEST_RUNNER=local
#   remotely  when TEST_RUNNER.<os>-<arch> (else TEST_RUNNER) names a runner:
#               ssh:[user@]host[:port]   docker:<image>[@<platform>]
#               cmd:<program>            local
#             scripts/cross-test.sh stages the tests with what they load, runs
#             kyua on the target and brings the reports back
#   not at all  a foreign target with no runner: `bmake test` stops, before
#             building, naming the variables to set -- never target binaries
#             run on the wrong machine (cross-test-needs-runner-req).
# Set the variables on the command line or in the hook files (pre.mk, local.mk),
# like every other setting; BMK_SSH_OPTS gives ssh its key and options.
# @impl 0f87-6adc-9b69-7c32

.if !defined(_MK_CROSSTEST_MK_)
_MK_CROSSTEST_MK_ = 1

# (_ATF_BUNDLED, _ATFB_MODE: the ATF Bmake It carries, mk.atf.mk)
.include "${BMK_MKDIR}/mk.atf.mk"

TEST_RUNNER ?=
_XTEST_KEY     = ${TARGET}-${TARGET_ARCH}
_XTEST_RUNNER  = ${TEST_RUNNER.${_XTEST_KEY}:U${TEST_RUNNER}}

_XTEST_FOREIGN = no
.if ${TARGET} != ${_HOST_OS_LABEL} || ${TARGET_ARCH} != ${_HOST_ARCH_LABEL}
_XTEST_FOREIGN = yes
.endif

.if "${_XTEST_RUNNER}" == "local" || ("${_XTEST_RUNNER}" == "" && ${_XTEST_FOREIGN} == "no")
_XTEST_MODE = local
.elif "${_XTEST_RUNNER}" == ""
_XTEST_MODE = missing
.else
_XTEST_MODE = remote
.endif

# TEST_RUNNER=local for a foreign Linux target: the host runs the target's
# programs through a user-mode emulator (qemu-user's binfmt, as Docker
# installs), which looks for the target's dynamic loader and libraries on
# the host -- "qemu-x86_64: Could not open '/lib64/ld-linux-x86-64.so.2'",
# testing linux-amd64 on an arm64 Linux host. QEMU_LD_PREFIX (unless
# already set) points it at BMK_LINUX_SYSROOT; exported to kyua, it reaches
# the test programs and the programs test scripts run. With it, OpenRider's
# 209 tests pass for linux-amd64 on linux-arm64.
# @impl 0f87-6adc-d562-38f8
_XTEST_LOCAL_ENV =
.if ${_XTEST_MODE} == "local" && ${_XTEST_FOREIGN} == "yes" && ${TARGET} == "linux" && !empty(BMK_LINUX_SYSROOT)
_XTEST_LOCAL_ENV = export QEMU_LD_PREFIX="${QEMU_LD_PREFIX:U${BMK_LINUX_SYSROOT}}";
.endif
# Windows has no rpath: a test program finds the DLLs it links (the
# module's own, the LIBS= chain) through PATH, as `bmake run` gives them --
# else it cannot start (Cygwin, 2026-10-28).
# @impl 7854-6ae2-336d-dd77
# (the module's lib/, the LIBS= search chain, the framework's lib/ -- a
# .tst module without TEST_PROG has no search chain of its own)
_XTEST_WIN_DLLDIRS = ${.CURDIR}/${BUILD_ROOT}/lib ${_LIB_SEARCH_DIRS:U} ${_FWDIR:D${_FWDIR}/${BUILD_ROOT}/lib}
.if ${_XTEST_MODE} == "local" && ${TARGET} == "win"
_XTEST_LOCAL_ENV = PATH="${_XTEST_WIN_DLLDIRS:O:u:ts:}:$$PATH"; export PATH;
.endif
# A native test program (MSVC, mingw) run by the Cygwin Kyua is handed
# Cygwin paths (its result file under /tmp/kyua.*): ATFW_CYGROOT lets
# Bmake It's ATF for Windows make them Windows paths (contrib/atf-bmk/win).
.if ${_XTEST_MODE} == "local" && ${_ATFB_MODE} == "win"
_XTEST_LOCAL_ENV += ATFW_CYGROOT="$$(cygpath -m /)"; export ATFW_CYGROOT;
.endif

# A native Windows runtime (ABI=mingw, TOOLCHAIN=msvc) has no ATF of its
# own: on a Cygwin host Bmake It builds one (_ATFB_MODE=win, mk.atf.mk); elsewhere
# (a cross build to Windows) `bmake test` says so up front instead of
# failing at the link.
_XTEST_NATIVE_WIN = no
.if ${TARGET} == "win" && (${TOOLCHAIN} == "msvc" || ${ABI:U} == "mingw") && "${_ATFB_MODE}" != "win"
_XTEST_NATIVE_WIN = yes
.endif

# The loader's search path variable on the target (Windows: PATH -- the
# shipped DLLs were not found under LD_LIBRARY_PATH, case 99 on Cygwin).
.if ${TARGET} == "macos"
_XTEST_LIBVAR = DYLD_LIBRARY_PATH
.elif ${TARGET} == "win"
_XTEST_LIBVAR = PATH
.else
_XTEST_LIBVAR = LD_LIBRARY_PATH
.endif

# The directories the test programs load libraries from: the module's own and
# every -Wl,-rpath the link used (the LIBS= chain). They are shipped and named
# by ${_XTEST_LIBVAR} on the target; the rpath into the build host is not used.
_XTEST_LIBDIRS = ${.CURDIR}/${BUILD_ROOT}/lib ${LDFLAGS:M-Wl,-rpath,*:S/^-Wl,-rpath,//}
# Windows links have no rpath: the DLL directories instead
.if ${TARGET} == "win"
_XTEST_LIBDIRS = ${_XTEST_WIN_DLLDIRS:O:u}
.endif

_XTEST_SCRIPT = ${BMK_MKDIR}/../scripts/cross-test.sh

# Stops `bmake test` early, naming what to set, for a foreign target without a
# runner. A prerequisite of `test`, ahead of the build.
_xtest_check:
.if ${_XTEST_NATIVE_WIN} == "yes"
	@echo "error: bmake test for ${TOOLCHAIN:Mmsvc:?TOOLCHAIN=msvc:ABI=mingw} output runs only on a Windows host with Cygwin: Bmake It builds the ATF for that runtime there, and the Cygwin Kyua runs the tests." >&2; \
	echo "       Run bmake test on the Windows host, or test this code on another target." >&2; \
	exit 1
.elif ${_XTEST_MODE} == "missing"
	@echo "error: bmake test for TARGET=${TARGET} TARGET_ARCH=${TARGET_ARCH} cannot run its tests on this host (${_HOST_OS_LABEL}-${_HOST_ARCH_LABEL})." >&2; \
	echo "       Name where to run them: TEST_RUNNER.${_XTEST_KEY}=ssh:[user@]host[:port] | docker:<image>[@<platform>] | cmd:<program>" >&2; \
	echo "       (or TEST_RUNNER=<spec> for every target), or TEST_RUNNER=local to run them here anyway. See docs/spec/80-unit-testing.md." >&2; \
	exit 1
.else
	@:
.endif

.PHONY: _xtest_check

.endif # _MK_CROSSTEST_MK_
