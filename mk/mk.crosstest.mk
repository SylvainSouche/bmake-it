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

# The loader's search path variable on the target.
.if ${TARGET} == "macos"
_XTEST_LIBVAR = DYLD_LIBRARY_PATH
.else
_XTEST_LIBVAR = LD_LIBRARY_PATH
.endif

# The directories the test programs load libraries from: the module's own and
# every -Wl,-rpath the link used (the LIBS= chain). They are shipped and named
# by ${_XTEST_LIBVAR} on the target; the rpath into the build host is not used.
_XTEST_LIBDIRS = ${.CURDIR}/${BUILD_ROOT}/lib ${LDFLAGS:M-Wl,-rpath,*:S/^-Wl,-rpath,//}

_XTEST_SCRIPT = ${BMK_MKDIR}/../scripts/cross-test.sh

# Stops `bmake test` early, naming what to set, for a foreign target without a
# runner. A prerequisite of `test`, ahead of the build.
_xtest_check:
.if ${_XTEST_MODE} == "missing"
	@echo "error: bmake test for TARGET=${TARGET} TARGET_ARCH=${TARGET_ARCH} cannot run its tests on this host (${_HOST_OS_LABEL}-${_HOST_ARCH_LABEL})." >&2; \
	echo "       Name where to run them: TEST_RUNNER.${_XTEST_KEY}=ssh:[user@]host[:port] | docker:<image>[@<platform>] | cmd:<program>" >&2; \
	echo "       (or TEST_RUNNER=<spec> for every target), or TEST_RUNNER=local to run them here anyway. See docs/spec/80-unit-testing.md." >&2; \
	exit 1
.else
	@:
.endif

.PHONY: _xtest_check

.endif # _MK_CROSSTEST_MK_
