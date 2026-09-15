# mk.test.mk — ATF/Kyua-based unit testing (unit-test-atf-kyua-adoption-req)
# Included by mk.prog.mk / mk.lib.mk. A module declares TESTS_CXX=/
# TESTS_C=/TESTS_SH= naming test programs; sources are looked up by
# convention in tests/<name>.cpp / tests/<name>.c / tests/<name>.sh.
# Compiled tests link against atf-c++/atf-c plus this module's own build
# output; all three kinds are registered in a generated Kyuafile and run
# via `kyua test`, agnostic to which kind produced the pass/fail
# (unit-test-feature-for-built-software-req).
#
# Verified end-to-end against MacPorts atf 0.21 / kyua 0.14.1 / lua 5.3.6
# (2026-09-15): compile+link+run+JUnit+HTML all confirmed on a real
# atf-c++ test case, both passing and (deliberately, temporarily) failing.
# Two real toolchain/product bugs surfaced and were fixed as part of this
# verification, not speculative: libc++'s C++17 mode drops std::auto_ptr,
# which MacPorts' atf-c++ 0.21 headers still use (see
# _LIBCPP_ENABLE_CXX17_REMOVED_AUTO_PTR below); and shared libs need an
# @rpath install name plus a matching consumer-side -Wl,-rpath to be
# loadable at all before any install step (see mk.lib.mk/mk.prog.mk).

.if !defined(_MK_TEST_MK_)
_MK_TEST_MK_ = 1

KYUA ?= kyua
TESTS_CXX ?=
TESTS_C ?=
TESTS_SH ?=

.if !empty(TESTS_CXX) || !empty(TESTS_C) || !empty(TESTS_SH)

_TEST_BINDIR = ${.CURDIR}/${BUILD_ROOT}/tests
_KYUAFILE = ${.CURDIR}/${BUILD_ROOT}/tests/Kyuafile

# atf-c++/atf-c compile+link flags -- via pkg-config, confirmed present on
# MacPorts (atf-c++.pc/atf-c.pc) and NetBSD/FreeBSD base; -latf-c++/-latf-c
# fallback kept for hosts without pkg-config for these.
_ATF_CXX_LIBS != pkg-config --libs atf-c++ 2>/dev/null || echo -latf-c++
# -D_LIBCPP_ENABLE_CXX17_REMOVED_AUTO_PTR: MacPorts' atf-c++ 0.21 headers
# (tests.hpp) still use std::auto_ptr, which libc++ drops under C++17 mode
# (clang's default since ~16) though libstdc++/gcc keeps it deprecated-but-
# present. No-op under libstdc++ -- confirmed toolchain gap, harmless fix.
_ATF_CXX_CFLAGS != pkg-config --cflags atf-c++ 2>/dev/null || echo ""
_ATF_CXX_CFLAGS += -D_LIBCPP_ENABLE_CXX17_REMOVED_AUTO_PTR
_ATF_C_LIBS != pkg-config --libs atf-c 2>/dev/null || echo -latf-c
_ATF_C_CFLAGS != pkg-config --cflags atf-c 2>/dev/null || echo ""

# Runtime search path so the test binary can load the module's own
# just-built shared lib without it being installed anywhere -- same
# reasoning as mk.lib.mk/mk.prog.mk's LIBS= rpath handling. No rpath
# concept on Windows.
# @impl 0f87-6aa9-448d-537c
_TEST_RPATH =
.if ${TARGET} != "win"
_TEST_RPATH = -Wl,-rpath,${.CURDIR}/${BUILD_ROOT}/lib
.endif

_build_tests:
	@mkdir -p ${_TEST_BINDIR}
.for _t in ${TESTS_CXX}
	@echo "===> building test ${_t} (atf-c++)"
	${CXX} ${CXXFLAGS} ${_ATF_CXX_CFLAGS} -I${.CURDIR}/include \
		${.CURDIR}/tests/${_t}.cpp -o ${_TEST_BINDIR}/${_t} \
		-L${.CURDIR}/${BUILD_ROOT}/lib -l${LIB} ${_TEST_RPATH} ${_ATF_CXX_LIBS}
.endfor
.for _t in ${TESTS_C}
	@echo "===> building test ${_t} (atf-c)"
	${CC} ${CFLAGS} ${_ATF_C_CFLAGS} -I${.CURDIR}/include \
		${.CURDIR}/tests/${_t}.c -o ${_TEST_BINDIR}/${_t} \
		-L${.CURDIR}/${BUILD_ROOT}/lib -l${LIB} ${_TEST_RPATH} ${_ATF_C_LIBS}
.endfor
.for _t in ${TESTS_SH}
	@echo "===> staging test ${_t} (atf-sh)"
	cp ${.CURDIR}/tests/${_t}.sh ${_TEST_BINDIR}/${_t}
	chmod +x ${_TEST_BINDIR}/${_t}
.endfor

_gen_kyuafile:
	@echo 'syntax(2)' > ${_KYUAFILE}
	@echo 'test_suite("${.CURDIR:T}")' >> ${_KYUAFILE}
.for _t in ${TESTS_CXX} ${TESTS_C} ${TESTS_SH}
	@echo 'atf_test_program{name="${_t}"}' >> ${_KYUAFILE}
.endfor

# test: build + run this module's declared tests, report JUnit XML, and
# exit non-zero if any test failed -- the JUnit report is still written
# either way (a failure is exactly when you most want the report), but a
# silently-zero exit on real failures would defeat a CI test target.
# @impl 0f87-6aa9-0267-4adc
test: _build_tests _gen_kyuafile
	@_rc=0; \
	(cd ${_TEST_BINDIR} && ${KYUA} test -k Kyuafile) || _rc=$$?; \
	(cd ${_TEST_BINDIR} && ${KYUA} report-junit --output=${.CURDIR}/${BUILD_ROOT}/test-results.xml); \
	echo "===> test results: ${BUILD_ROOT}/test-results.xml"; \
	exit $$_rc

# test-all: same, plus a full HTML report (unit-test-full-suite-html-report-req).
# Self-contained rather than depending on `test` -- a failing `test` target
# would abort make before this recipe runs, and the HTML report must be
# produced on failure too, not only on success.
test-all: _build_tests _gen_kyuafile
	@_rc=0; \
	(cd ${_TEST_BINDIR} && ${KYUA} test -k Kyuafile) || _rc=$$?; \
	(cd ${_TEST_BINDIR} && ${KYUA} report-junit --output=${.CURDIR}/${BUILD_ROOT}/test-results.xml); \
	(cd ${_TEST_BINDIR} && ${KYUA} report-html --force --output=${.CURDIR}/${BUILD_ROOT}/test-report-html); \
	echo "===> test results: ${BUILD_ROOT}/test-results.xml"; \
	echo "===> full HTML report: ${BUILD_ROOT}/test-report-html/index.html"; \
	exit $$_rc

.else
test:
	@echo "no TESTS_CXX/TESTS_C/TESTS_SH declared in ${.CURDIR:T}"
test-all: test
.endif

.PHONY: test test-all _build_tests _gen_kyuafile

.endif # _MK_TEST_MK_
