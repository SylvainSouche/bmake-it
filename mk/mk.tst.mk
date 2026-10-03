# mk.tst.mk -- a <name>.tst test module (tst-module-layout-req,
# tst-scripts-are-tests-req, tst-test-prog-req, tst-test-srcs-req,
# tst-test-environment-req; tst-test-modules-dec).
#
#   raster.tst/
#     makefile      PROG=raster_util  TEST_PROG=raster_test  TEST_SRCS=raster_test.cpp  LIBS=geo
#                   .include <mk.tst.mk>
#     src/          compiled sources
#     testcases/    *.sh -- each one is a test (atf-sh)
#
# - testcases/*.sh are auto-discovered; each is registered with Kyua as an
#   atf-sh test program.
# - PROG=<name> builds a UTILITY the scripts use: built, not registered.
# - TEST_PROG=<name> builds a program that IS an ATF test program: registered.
#   TEST_PROG= alone builds it from all of src/ (or TEST_SRCS=); with PROG=
#   also set, TEST_SRCS= names its sources (relative to src/) and PROG is
#   built from the rest -- setting both without TEST_SRCS= is an error.
# - A module with neither is scripts-only.
# - BUILT by a plain bmake (a compile error in a test surfaces at build
#   time), but never shipped: no copy-up, install or distrib. `test` runs it.
# - The scripts see the RESULTING build output, not just their own module:
#   the module's test dir, its framework's bin, the workspace's bin and each
#   PARENT_WS's bin on PATH, and BMK_SHAREDIR (colon-separated, same order)
#   for shipped helper scripts. Using an executable outside PREREQS= is bad
#   practice, documented as such, and deliberately not diagnosed.
# @impl 0f87-6ac0-d892-bc8f
# @impl 0f87-6ac0-d893-88fa

.if !defined(_MK_TST_MK_)
_MK_TST_MK_ = 1
_BMK_TST = yes

.if !defined(BMK_MKDIR)
.  if exists(${.PARSEDIR}/mk.common.mk)
BMK_MKDIR := ${.PARSEDIR}
.  else
BMK_MKDIR = ${.CURDIR}
.  endif
.endif

TEST_PROG ?=
TEST_SRCS ?=
KYUA ?= kyua

_TST_HAS_PROG = no
.if defined(PROG) && !empty(PROG)
_TST_HAS_PROG = yes
.endif
_TST_HAS_TEST = no
.if !empty(TEST_PROG)
_TST_HAS_TEST = yes
.endif

_TST_ALLSRCS != find src -type f \( -name '*.c' -o -name '*.cc' -o -name '*.cpp' -o -name '*.cxx' \) ! -path '*/.*' 2>/dev/null | sed 's|^src/||' || true

# --- which sources build what -------------------------------------------
.if ${_TST_HAS_PROG} == "yes" && ${_TST_HAS_TEST} == "yes"
.  if empty(TEST_SRCS)
.    error "${.CURDIR:T}: PROG= and TEST_PROG= are both set, so TEST_SRCS= must name the test program's sources (relative to src/); PROG is built from the rest"
.  endif
_TST_USRCS =
.  for _s in ${_TST_ALLSRCS}
_tst_m = ${TEST_SRCS:M${_s}}
.    if empty(_tst_m)
_TST_USRCS += ${_s}
.    endif
.  endfor
.  if empty(_TST_USRCS)
.    error "${.CURDIR:T}: PROG=${PROG} has no sources left once TEST_SRCS=${TEST_SRCS} is taken out of src/"
.  endif
SRCS = ${_TST_USRCS}
_TST_TSRCS = ${TEST_SRCS}
.elif ${_TST_HAS_TEST} == "yes"
PROG = ${TEST_PROG}
.  if !empty(TEST_SRCS)
SRCS = ${TEST_SRCS}
_TST_TSRCS = ${TEST_SRCS}
.  else
_TST_TSRCS = ${_TST_ALLSRCS}
.  endif
.endif

# --- ATF flavour: C++ if any test source is C++ -----------------------------
_TST_FLAVOR = c
.if ${_TST_HAS_TEST} == "yes"
.  for _e in cpp cc cxx
_tst_x = ${_TST_TSRCS:M*.${_e}}
.    if !empty(_tst_x)
_TST_FLAVOR = cxx
.    endif
.  endfor
.  if ${_TST_FLAVOR} == "cxx"
_TST_ATF_CFLAGS != pkg-config --cflags atf-c++ 2>/dev/null || echo ""
_TST_ATF_CFLAGS += -D_LIBCPP_ENABLE_CXX17_REMOVED_AUTO_PTR
_TST_ATF_LIBS != pkg-config --libs atf-c++ 2>/dev/null || echo -latf-c++
.  else
_TST_ATF_CFLAGS != pkg-config --cflags atf-c 2>/dev/null || echo ""
_TST_ATF_LIBS != pkg-config --libs atf-c 2>/dev/null || echo -latf-c
.  endif
.endif

# TEST_PROG= alone: mk.prog.mk builds it, so it needs the ATF flags itself.
.if ${_TST_HAS_TEST} == "yes" && ${_TST_HAS_PROG} == "no"
CFLAGS   += ${_TST_ATF_CFLAGS}
CXXFLAGS += ${_TST_ATF_CFLAGS}
LDFLAGS  += ${_TST_ATF_LIBS}
.endif

_TST_SCRIPTS != ls testcases/*.sh 2>/dev/null | sed 's|^testcases/||' || true
_TST_TESTNAMES = ${TEST_PROG} ${_TST_SCRIPTS}

# --- the module itself ----------------------------------------------------------
.if ${_TST_HAS_PROG} == "yes" || ${_TST_HAS_TEST} == "yes"
.  include "${BMK_MKDIR}/mk.prog.mk"
.else
# Scripts-only: nothing to compile. Still honours PLATFORMS=/TOOLCHAINS=.
.  include "${BMK_MKDIR}/mk.common.mk"
.  include "${BMK_MKDIR}/mk.constraints.mk"
.  if ${_BMK_BUILD} == "yes"
_FWDIR = ${.CURDIR}/..
.MAIN: all
all:
	@:
clean:
	rm -rf ${.CURDIR}/${BUILD_ROOT}
.PHONY: all clean
.  else
_SK_ROLE = module
.    include "${BMK_MKDIR}/mk.skipped.mk"
.  endif
.endif

.if ${_BMK_BUILD} == "yes"

_TST_BINDIR = ${.CURDIR}/${BUILD_ROOT}/tests
_TST_KYUAFILE = ${_TST_BINDIR}/Kyuafile
_WSROOT = ${.CURDIR}/../..

# PATH and BMK_SHAREDIR: this module's test dir, its framework's output, the
# workspace's, then each PARENT_WS's.
_TST_PATH = ${_TST_BINDIR}:${_FWDIR}/${BINDIR_LOCAL}:${_WSROOT}/${BINDIR_LOCAL}
_TST_SHARE = ${_FWDIR}/${SHAREDIR_LOCAL}:${_WSROOT}/${SHAREDIR_LOCAL}
.  for _p in ${PARENT_WS}
_TST_PATH := ${_TST_PATH}:${_p}/${BINDIR_LOCAL}
_TST_SHARE := ${_TST_SHARE}:${_p}/${SHAREDIR_LOCAL}
.  endfor

.  if !empty(TEST)
_TST_SEL = ${_TST_TESTNAMES:M${TEST}}
.  else
_TST_SEL = ${_TST_TESTNAMES}
.  endif

.  if ${_TST_HAS_PROG} == "yes" || ${_TST_HAS_TEST} == "yes"
_TST_STAGE_DEPS = all
.  else
_TST_STAGE_DEPS =
.  endif

# With PROG= and TEST_PROG= both set, the test program is compiled from
# TEST_SRCS= as part of `all` (a test's compile error surfaces at build
# time), into the module's own bin/ -- never copied up.
.  if ${_TST_HAS_PROG} == "yes" && ${_TST_HAS_TEST} == "yes"
_TST_TESTBIN = ${.CURDIR}/${BUILD_ROOT}/bin/${TEST_PROG}
${_TST_TESTBIN}: ${TEST_SRCS:S|^|${.CURDIR}/src/|} ${_LIBS_FILES}
	@mkdir -p ${.TARGET:H}
.    if ${_TST_FLAVOR} == "cxx"
	${CXX} ${CXXFLAGS} ${_TST_ATF_CFLAGS} -I${.CURDIR}/include \
		${TEST_SRCS:S|^|${.CURDIR}/src/|} -o ${.TARGET} ${LDFLAGS} ${_TST_ATF_LIBS}
.    else
	${CC} ${CFLAGS} ${_TST_ATF_CFLAGS} -I${.CURDIR}/include \
		${TEST_SRCS:S|^|${.CURDIR}/src/|} -o ${.TARGET} ${LDFLAGS} ${_TST_ATF_LIBS}
.    endif
	@echo "===> built test program ${TEST_PROG}"
all: ${_TST_TESTBIN}
.  endif

_tst_stage: ${_TST_STAGE_DEPS}
	@rm -rf ${_TST_BINDIR}; mkdir -p ${_TST_BINDIR}
.  if ${_TST_HAS_PROG} == "yes" && ${_TST_HAS_TEST} == "yes"
	cp ${_TST_TESTBIN} ${_TST_BINDIR}/${TEST_PROG}
	cp ${_BINOUT} ${_TST_BINDIR}/${PROG}
.  elif ${_TST_HAS_TEST} == "yes"
	cp ${_BINOUT} ${_TST_BINDIR}/${TEST_PROG}
.  elif ${_TST_HAS_PROG} == "yes"
	cp ${_BINOUT} ${_TST_BINDIR}/${PROG}
.  endif
.  for _s in ${_TST_SCRIPTS}
	cp ${.CURDIR}/testcases/${_s} ${_TST_BINDIR}/${_s}
	chmod +x ${_TST_BINDIR}/${_s}
.  endfor
	@echo 'syntax(2)' > ${_TST_KYUAFILE}
	@echo 'test_suite("${.CURDIR:T}")' >> ${_TST_KYUAFILE}
.  for _t in ${_TST_SEL}
	@echo 'atf_test_program{name="${_t}"}' >> ${_TST_KYUAFILE}
.  endfor

# @impl 0f87-6ac0-d892-bc8f
test: _tst_stage
.  if empty(_TST_SEL)
.    if !empty(TEST)
	@echo "error: TEST=${TEST} matches no test in ${.CURDIR:T}" >&2; exit 1
.    else
	@echo "no tests in ${.CURDIR:T} (no TEST_PROG=, no testcases/*.sh)"
.    endif
.  else
	@_rundir=${.CURDIR}/${BUILD_ROOT}/runs/${RUN_ID}; mkdir -p "$$_rundir"; \
	_rc=0; \
	export PATH="${_TST_PATH}:$$PATH" BMK_SHAREDIR="${_TST_SHARE}"; \
	(cd ${_TST_BINDIR} && ${KYUA} test -k Kyuafile) || _rc=$$?; \
	(cd ${_TST_BINDIR} && ${KYUA} report-junit --output="$$_rundir/test-results.xml"); \
	echo "===> test results: ${BUILD_ROOT}/runs/${RUN_ID}/test-results.xml"; \
	if [ "${REPORT}" = "yes" ]; then \
		(cd ${_TST_BINDIR} && ${KYUA} report-html --force --output="$$_rundir/test-report-html"); \
		echo "===> full HTML report: ${BUILD_ROOT}/runs/${RUN_ID}/test-report-html/index.html"; \
	fi; \
	rm -rf ${.CURDIR}/${BUILD_ROOT}/runs/latest; \
	cp -a "$$_rundir" ${.CURDIR}/${BUILD_ROOT}/runs/latest; \
	exit $$_rc
.  endif

.PHONY: test _tst_stage
.endif

.endif # _MK_TST_MK_
