# mk.framework.mk — framework role
# Usage:  PREREQS=System Other   (mandatory, may be empty)
#         .include <mk.framework.mk>

.if !defined(_MK_FRAMEWORK_MK_)
_MK_FRAMEWORK_MK_ = 1

.if !defined(BMK_MKDIR)
.  if exists(${.PARSEDIR}/mk.common.mk)
BMK_MKDIR := ${.PARSEDIR}
.  elif exists(${.CURDIR}/../mk/mk.common.mk)
BMK_MKDIR = ${.CURDIR}/../mk
.  elif exists(${.CURDIR}/../../mk/mk.common.mk)
BMK_MKDIR = ${.CURDIR}/../../mk
.  else
BMK_MKDIR = ${.CURDIR}
.  endif
.endif

.include "${BMK_MKDIR}/mk.common.mk"

# PREREQS is mandatory (even empty) — discovery signal
# @impl 0f87-6a98-76a7-f34f
.if !defined(PREREQS)
.  error "PREREQS= must be defined (even if empty) in a framework makefile"
.endif

# ---------------------------------------------------------------------------
# Local customization hooks (local-mk-hook-files-and-cascade-order-req)
# Framework level sees PARENT_WS's mk/ (outermost), then the workspace's
# own mk/, then its own -- outer to inner, all included, in that order.
# ---------------------------------------------------------------------------
_LOCAL_MK_DIRS =
.for _p in ${PARENT_WS}
_LOCAL_MK_DIRS += ${_p}/mk
.endfor
_LOCAL_MK_DIRS += ${.CURDIR}/../mk ${.CURDIR}/mk

_LOCAL_MK_PHASE = pre
.include "${BMK_MKDIR}/mk.local.mk"

# framework-level-constraint-req: a PLATFORMS=/TOOLCHAINS= declared here
# applies to the whole framework -- none of its modules is entered.
# @impl 0f87-6ac0-d892-5753
.include "${BMK_MKDIR}/mk.constraints.mk"
.if ${_BMK_BUILD} == "yes"

# ---------------------------------------------------------------------------
# Auto-discover modules (*.m) and generate topological order from LIBS=
# ---------------------------------------------------------------------------
_GEN_SCRIPT = ${BMK_MKDIR}/../scripts/gen-mod-order.sh
_ORDER_MK   = ${.CURDIR}/.gen-mod-order.mk

.if exists(${_GEN_SCRIPT})
# Force regenerate every parse; pass BMK_MKDIR so -V LIBS/LIB queries work
# @impl 0f87-6a98-5f76-2a44
# REQ-nested-invocation-reentrancy-guard-req: no longer `rm -f` the cache
# before regenerating -- gen-mod-order.sh now writes via temp-file-then-rename,
# so a concurrent or nested parse of this same directory never observes a
# missing or half-written cache; on failure the previous good cache survives.
#
# BMK_SYS_MK is passed through only if the caller already set it -- do NOT
# default it here: a hardcoded /opt/local/share/mk once short-circuited the
# sys.mk search on every non-macOS host (2026-08-31).
# @impl 0f87-6a98-5e9c-0a14
# order-query-sys-mk-located-req: the nested -V LIBS/LIB/PROG queries look
# for sys.mk where THIS bmake found it (.SYSPATH) before any hardcoded
# list -- /usr/share/mk:/opt/local/share/mk here missed Cygwin's
# /usr/share/bmake/mk (2026-10-15).
# @impl 7854-6ad0-c2da-f4ce
# order-query-failure-is-error-req: both times, the queries failed and the
# failure was swallowed, so every module looked dependency-free and was
# built in glob order -- a library's dependents before the library, dying
# later with "not built yet" or a missing header, nowhere near the cause.
# stderr is NOT captured now, so the generator's explanation reaches the
# terminal as written, and a failure stops this framework right here.
# @impl 7854-6ad0-c2da-1218
_order_generated != cd ${.CURDIR} && 	BMK_MKDIR='${BMK_MKDIR}' 	MAKESYSPATH='${BMK_MKDIR}:${.SYSPATH:U:ts:}' 	BMK_SYS_MK='${BMK_SYS_MK:U}' 	BMAKE='${MAKE}' 	sh ${_GEN_SCRIPT} ${_ORDER_MK} || echo "FAILED:$$?"
# order-failure-in-query-is-warning-req: a -V query still answers (as for
# REQUIRES=/constraint errors); only a build stops.
# @impl 7854-6ad0-c7d9-13f6
# clean too: it needs no build order, and must still reach a framework
# whose order cannot be computed (leftover-module-dir-skipped-and-cleaned-req).
.  if !empty(_order_generated:MFAILED*)
.    if empty(.MAKEFLAGS:M-V*) && !make(clean)
.      error module build order could not be determined (scripts/gen-mod-order.sh failed, its reason is printed above)
.    else
.      warning module build order could not be determined (scripts/gen-mod-order.sh failed, its reason is printed above); a build here will stop on it
.    endif
.  endif
.endif

.-include "${_ORDER_MK}"
.if defined(MODULE_SUBDIR) && !empty(MODULE_SUBDIR)
SUBDIR_MODULES := ${MODULE_SUBDIR}
.elif exists(${_GEN_SCRIPT})
# Generation succeeded and found no *.m: a framework with no modules.
SUBDIR_MODULES =
.else
.  error Bmake It installation incomplete: ${_GEN_SCRIPT} is missing, so module build order cannot be determined
.endif

# tst-module-layout-v2-req: <name>.tst test modules sit beside the .m modules.
# They are built by `all` (after every .m module) but never copied up or
# installed -- never shipped; `test` is what runs them. Discovery is just
# the suffix; they need no build order of their own.
# @impl 0f87-6ac0-d892-bc8f
# leftover-module-dir-skipped-and-cleaned-req: a *.tst without a makefile
# (a leftover after git switch) is not a test module.
# @impl 7854-6ad2-021e-2621
SUBDIR_TESTMODS != for _t in *.tst; do [ -f "$$_t/makefile" ] && echo "$$_t"; done; true

# Surface order in verbose builds
.if make(all) || make(_build_modules)
.  info framework modules (build order): ${SUBDIR_MODULES}
.endif

# ---------------------------------------------------------------------------
# Build all modules in dependency order, then copy-up. Each module's build
# output is always captured to <module>/<BUILD_ROOT>/runs/<RUN_ID>/build.log
# (tee'd, so console output is unchanged), with runs/latest kept pointing
# at it -- re-running the same arch-toolchain target does not overwrite a
# previous run's log (run-history-not-overwritten-req). One module's build
# failure does NOT stop every other module from still being attempted --
# FAIL_FAST=yes opts into stop-on-first-failure instead
# (build-workspace-aggregation-req-v2, report-flag-uniform-trigger-v2).
# ---------------------------------------------------------------------------
all: _check_requires _create_fw_dirs _build_modules _aggregate _check_build_failures
	@echo "===> framework ${.CURDIR:T} complete for ${OS_ARCH}"

# requires-preflight-req: before any module is built, ask every module that
# can lack something (MODULE_CHECK, from gen-mod-order.sh: a REQUIRES=, an
# IMPORT= or grammar sources) what it lacks -- the same checks as its own
# build, in report mode (BMK_REQUIRES_CHECK=yes), for this target -- plus
# Kyua and ATF when tests follow, and print ONE list, then stop. From the
# workspace (BMK_REQUIRES_LIST=<file>) the entries are added to the
# workspace's list instead, which it prints; frameworks it then builds are
# told BMK_REQUIRES_CHECKED=yes.
# @impl 7854-6ae3-0b4f-513f
_check_requires:
.if ${BMK_REQUIRES_CHECKED:U} != "yes"
	@if [ -n "${BMK_REQUIRES_LIST:U}" ]; then _list="${BMK_REQUIRES_LIST:U}"; else _list=$$(mktemp); fi; \
	for _m in ${MODULE_CHECK:U} ${SUBDIR_TESTMODS}; do \
		_err=$$(mktemp); \
		if _r=$$(${MAKE} -C ${.CURDIR}/$$_m -V '$${_REQUIRES_REPORT}' BMK_REQUIRES_CHECK=yes \
			TARGET=${TARGET} TARGET_ARCH=${TARGET_ARCH} TOOLCHAIN=${TOOLCHAIN} \
			BMK_MKDIR=${BMK_MKDIR} PARENT_WS="${PARENT_WS}" 2>"$$_err"); then \
			for _e in $$_r; do echo "${.CURDIR:T}/$$_m $$_e" >> "$$_list"; done; \
		else \
			_msg=$$(grep -v '^[[:space:]]' "$$_err" | head -1 | tr ' ' '\037'); \
			echo "${.CURDIR:T}/$$_m ?%query=$$_msg" >> "$$_list"; \
		fi; \
		rm -f "$$_err"; \
	done; \
	case " ${BMK_REQUIRES_FOR:U${.TARGETS}} " in *" test "*) \
		_k=$$(command -v ${KYUA:Ukyua} 2>/dev/null) || echo "* kyua%tool" >> "$$_list"; \
		if [ -n "$$_k" ]; then \
			PKG_CONFIG_PATH="$$(dirname "$$(dirname "$$_k")")/lib/pkgconfig$${PKG_CONFIG_PATH:+:$$PKG_CONFIG_PATH}" \
				pkg-config --exists atf-c 2>/dev/null || echo "* atf-c%pkg" >> "$$_list"; \
		fi ;; \
	esac; \
	if [ -z "${BMK_REQUIRES_LIST:U}" ]; then \
		_rc=0; sh ${BMK_MKDIR}/../scripts/requires-report.sh "$$_list" || _rc=$$?; rm -f "$$_list"; exit $$_rc; \
	fi
.else
	@:
.endif

# aggregation-failure-exit-code-req: FAIL_FAST=no already lets every
# module build regardless of an earlier failure (_build_modules: never
# exits early for that reason) -- but each .for iteration is its own
# shell command ending in a `cp -a` that always succeeds, so the module's
# real failure was invisible to bmake's own recipe-line exit tracking.
# This step runs last (after _aggregate, so whatever DID succeed is still
# copied up/aggregated) and turns the build.failed markers _build_modules:
# already writes into the framework's own real exit code.
# @impl 0f87-6ab5-81a2-7bb0
_check_build_failures:
	@_failed=""; \
	for _m in ${SUBDIR_MODULES} ${SUBDIR_TESTMODS}; do \
		if [ -f "${.CURDIR}/$$_m/${BUILD_ROOT}/runs/${RUN_ID}/build.failed" ]; then \
			_failed="$$_failed $$_m"; \
		fi; \
	done; \
	if [ -n "$$_failed" ]; then \
		echo "===> framework ${.CURDIR:T} BUILD FAILED:$$_failed" >&2; \
		for _m in $$_failed; do \
			_sk="${.CURDIR}/$$_m/${BUILD_ROOT}/runs/${RUN_ID}/build.skipped"; \
			if [ -f "$$_sk" ]; then \
				echo "     $$_m -- skipped: its prerequisite $$(cat "$$_sk") failed" >&2; \
			else \
				echo "     $$_m -- see $$_m/${BUILD_ROOT}/runs/${RUN_ID}/build.log" >&2; \
			fi; \
		done; \
		exit 1; \
	fi

# single-module-visit-req: `all copy-up` is ONE make invocation per
# module (it was two: build, then a second process just for copy-up, which
# re-parsed the whole makefile chain -- IMPORT= resolution included --
# only to find nothing to do). `all` failing stops the invocation, so
# copy-up still never runs after a failed build.
# @impl 0f87-6abf-aeba-b9eb
# @impl 0f87-6a98-5e47-0c71
# @impl 0f87-6aaa-6a6e-00d0
# @impl 0f87-6aaa-72d2-8ffc
# The exit status is kept with `&& echo 0 || echo $$?`: a make that runs
# recipes under sh -e (FreeBSD's) ended the group at a failed module before
# a following `echo $$?`, leaving it empty ("[: : bad number", 2026-10-29).
# module-skipped-after-failed-prereq-req: a module whose prerequisite module
# (LIBS= within this framework, MODULE_DEPS from gen-mod-order.sh) failed or
# was skipped in this run is skipped, one line saying why -- it would only
# fail again on that module's missing headers ("'GLFW/glfw3.h' file not
# found" for imgui after glfw's REQUIRES failed, 2026-10-29).
# @impl 7854-6ae3-0a48-eaaa
_build_modules:
.for _m in ${SUBDIR_MODULES}
	@_rundir=${.CURDIR}/${_m}/${BUILD_ROOT}/runs/${RUN_ID}; mkdir -p "$$_rundir"; \
	_skip=""; _root=""; \
	for _d in ${MODULE_DEPS.${_m}:U}; do \
		if [ -f "${.CURDIR}/$$_d/${BUILD_ROOT}/runs/${RUN_ID}/build.failed" ]; then \
			_skip=$$_d; _root=$$(cat "${.CURDIR}/$$_d/${BUILD_ROOT}/runs/${RUN_ID}/build.skipped" 2>/dev/null || true); \
			[ -n "$$_root" ] || _root=$$_d; break; \
		fi; \
	done; \
	if [ -n "$$_skip" ]; then \
		_why="prerequisite module $$_skip failed"; [ "$$_root" = "$$_skip" ] || _why="$$_why (root cause: $$_root)"; \
		echo "===> module ${_m} skipped: $$_why" | tee "$$_rundir/build.log"; \
		echo "$$_root" > "$$_rundir/build.skipped"; touch "$$_rundir/build.failed"; \
		rm -rf ${.CURDIR}/${_m}/${BUILD_ROOT}/runs/latest; cp -a "$$_rundir" ${.CURDIR}/${_m}/${BUILD_ROOT}/runs/latest; \
		if [ "${FAIL_FAST}" = "yes" ]; then exit 1; fi; \
		exit 0; \
	fi; \
	rm -f "$$_rundir/build.skipped"; \
	echo "===> building module ${_m}"; \
	_rcfile=$$(mktemp); \
	{ ${MAKE} -C ${_m} all copy-up \
		TARGET=${TARGET} TARGET_ARCH=${TARGET_ARCH} TOOLCHAIN=${TOOLCHAIN} \
		BMK_MKDIR=${BMK_MKDIR} PARENT_WS="${PARENT_WS}" SANITIZE="${SANITIZE}" FAIL_FAST="${FAIL_FAST}" RUN_ID="${RUN_ID}" \
	  && echo 0 > "$$_rcfile" || echo $$? > "$$_rcfile"; } 2>&1 | tee "$$_rundir/build.log"; \
	_rc=$$(cat "$$_rcfile"); rm -f "$$_rcfile"; \
	if [ "$$_rc" -eq 0 ]; then \
		rm -f "$$_rundir/build.failed"; \
	else \
		touch "$$_rundir/build.failed"; \
		echo "===> module ${_m} build FAILED -- see ${_m}/${BUILD_ROOT}/runs/${RUN_ID}/build.log" >&2; \
		if [ "${FAIL_FAST}" = "yes" ]; then exit 1; fi; \
	fi; \
	rm -rf ${.CURDIR}/${_m}/${BUILD_ROOT}/runs/latest; \
	cp -a "$$_rundir" ${.CURDIR}/${_m}/${BUILD_ROOT}/runs/latest
.endfor
# tst-modules-built-not-shipped-dec: .tst modules are built too, after every
# .m module is built and copied up (they link its libraries), but with `all`
# only -- no copy-up, so a test is never aggregated into the framework or
# workspace bin/lib and never shipped.
.for _m in ${SUBDIR_TESTMODS}
	@echo "===> building module ${_m}"
	@_rundir=${.CURDIR}/${_m}/${BUILD_ROOT}/runs/${RUN_ID}; mkdir -p "$$_rundir"; \
	_rcfile=$$(mktemp); \
	{ ${MAKE} -C ${_m} all \
		TARGET=${TARGET} TARGET_ARCH=${TARGET_ARCH} TOOLCHAIN=${TOOLCHAIN} \
		BMK_MKDIR=${BMK_MKDIR} PARENT_WS="${PARENT_WS}" SANITIZE="${SANITIZE}" FAIL_FAST="${FAIL_FAST}" RUN_ID="${RUN_ID}" \
	  && echo 0 > "$$_rcfile" || echo $$? > "$$_rcfile"; } 2>&1 | tee "$$_rundir/build.log"; \
	_rc=$$(cat "$$_rcfile"); rm -f "$$_rcfile"; \
	if [ "$$_rc" -eq 0 ]; then \
		rm -f "$$_rundir/build.failed"; \
	else \
		touch "$$_rundir/build.failed"; \
		echo "===> module ${_m} build FAILED -- see ${_m}/${BUILD_ROOT}/runs/${RUN_ID}/build.log" >&2; \
		if [ "${FAIL_FAST}" = "yes" ]; then exit 1; fi; \
	fi; \
	rm -rf ${.CURDIR}/${_m}/${BUILD_ROOT}/runs/latest; \
	cp -a "$$_rundir" ${.CURDIR}/${_m}/${BUILD_ROOT}/runs/latest
.endfor

# test: recurse into every module (test-workspace-aggregation-req). A
# module with no TESTS_CXX=/TESTS_C=/TESTS_SH= just echoes and exits 0
# (mk.test.mk's own no-tests branch). One module's genuine test failure
# does NOT stop the loop before every other module has had a chance to
# run, unless FAIL_FAST=yes was given. REPORT=/SANITIZE=/RUN_ID= are
# forwarded as-is; TEST=<name> is pre-filtered here -- only modules that
# actually declare a matching test get invoked at all, so mk.test.mk's
# own TEST=-with-no-match case only ever fires for a genuine direct
# mistake, not for every module TEST= wasn't meant for.
# @impl 0f87-6aaa-6201-a430
# @impl 0f87-6aaa-697c-4c30
# @impl 0f87-6ab5-81a2-7bb0
# test-builds-prerequisite-closure-req: `test` is preceded by a build of
# everything it can reach. Found in real use: from a clean tree, `bmake test`
# at the workspace never entered a prerequisite framework that has no tests
# (GIS, GUI), so the headers it imports were never staged and a tested
# framework failed with "'glm/glm.hpp' file not found". Here, the framework
# builds the PREREQS= closure found in the same workspace (depth first,
# cycle-guarded; a prerequisite from a PARENT_WS is built in its own
# workspace) and its own modules, copied up, plus share/. The workspace's
# `test` builds everything once itself and passes BMK_TEST_BUILT=yes.
# @impl 0f87-6ac1-0a1e-c402
.include "${BMK_MKDIR}/mk.crosstest.mk"
test: _xtest_check _fw_test_build _run_tests _check_test_failures

.if defined(BMK_TEST_BUILT) && ${BMK_TEST_BUILT} == "yes"
_fw_test_build:
	@:
.else
_fw_test_build: _fw_build_closure
.endif

_fw_build_closure: _check_requires _fw_build_prereqs _create_fw_dirs _build_modules _aggregate _check_build_failures

_fw_build_prereqs:
.for _p in ${PREREQS}
	@if [ -f "${.CURDIR}/../${_p}/makefile" ]; then \
		case " ${BMK_CLOSURE} " in *" ${_p} "*) exit 0 ;; esac; \
		${MAKE} -C ${.CURDIR}/../${_p} _fw_build_closure \
			TARGET=${TARGET} TARGET_ARCH=${TARGET_ARCH} TOOLCHAIN=${TOOLCHAIN} \
			BMK_MKDIR=${BMK_MKDIR} PARENT_WS="${PARENT_WS}" SANITIZE="${SANITIZE}" FAIL_FAST="${FAIL_FAST}" \
			RUN_ID="${RUN_ID}" BMK_CLOSURE="${BMK_CLOSURE} ${.CURDIR:T}" || exit 1; \
	fi
.endfor

# @impl 0f87-6ad7-1f32-4d7a
# `|| _trc=$$?`, not a following `_trc=$$?`: make may run this line under
# sh -e, which would stop the loop at the first failing module.
_run_tests:
.for _m in ${SUBDIR_MODULES} ${SUBDIR_TESTMODS}
	@if [ -n "${TEST}" ]; then \
		_has=$$(${MAKE} -C ${_m} -V '$${TESTS_CXX} $${TESTS_C} $${TESTS_SH} $${_TST_TESTNAMES}' 2>/dev/null); \
		case " $$_has " in \
			*" ${TEST} "*) _run=yes ;; \
			*) _run=no ;; \
		esac; \
	else \
		_run=yes; \
	fi; \
	if [ "$$_run" = yes ]; then \
		_rundir=${.CURDIR}/${_m}/${BUILD_ROOT}/runs/${RUN_ID}; mkdir -p "$$_rundir"; \
		_trc=0; \
		${MAKE} -C ${_m} test \
			TARGET=${TARGET} TARGET_ARCH=${TARGET_ARCH} TOOLCHAIN=${TOOLCHAIN} \
			BMK_MKDIR=${BMK_MKDIR} PARENT_WS="${PARENT_WS}" SANITIZE="${SANITIZE}" FAIL_FAST="${FAIL_FAST}" \
			REPORT="${REPORT}" TEST="${TEST}" RUN_ID="${RUN_ID}" || _trc=$$?; \
		if [ "$$_trc" -ne 0 ]; then \
			touch "$$_rundir/test.failed"; \
			if [ "${FAIL_FAST}" = "yes" ]; then exit $$_trc; fi; \
		else \
			rm -f "$$_rundir/test.failed"; \
		fi; \
	fi
.endfor

# aggregation-failure-exit-code-req: same reasoning as _check_build_failures
# -- $$_trc above is already correct per iteration, but each iteration is
# its own shell command, so the marker is what survives to this final step.
# @impl 0f87-6ab5-81a2-7bb0
_check_test_failures:
	@_failed=""; \
	for _m in ${SUBDIR_MODULES} ${SUBDIR_TESTMODS}; do \
		if [ -f "${.CURDIR}/$$_m/${BUILD_ROOT}/runs/${RUN_ID}/test.failed" ]; then \
			_failed="$$_failed $$_m"; \
		fi; \
	done; \
	if [ -n "$$_failed" ]; then \
		echo "===> framework ${.CURDIR:T} TEST FAILED:$$_failed" >&2; \
		for _m in $$_failed; do \
			echo "     $$_m -- see $$_m/${BUILD_ROOT}/runs/${RUN_ID}/test-results.xml" >&2; \
		done; \
		exit 1; \
	fi

# framework-dir-creation-ordering-fix-req: build/<key>/{bin,lib,share,
# include} must exist BEFORE any module in this framework is built, on
# EVERY pass -- not just after the first pass's _aggregate ran. Found
# empirically (direct reproduction, not assumed): mk.prog.mk/mk.lib.mk
# gate -I<fwdir>/build/<key>/include onto CFLAGS/CXXFLAGS with a parse-
# time exists() check; when dir creation was part of _aggregate (which
# ran AFTER _build_modules), a module parsed on a framework's first
# pass (directory absent) got no such -I, while the SAME module parsed
# on a second, fresh bmake pass (directory now exists, created by the
# first pass) silently gained one -- changing CFLAGS content between
# passes, which changed _check_inputs_hash's fingerprint, forcing a
# spurious recompile and re-archive whose new embedded `ar` timestamp
# then differed from the already-copied-up archive, producing a
# "copy-up collision ... differs -- overwriting" warning on an
# otherwise genuinely clean, unchanged build (confirmed via a minimal
# static-lib + consuming-app reproduction: `ar rcs` ran twice from a
# single clean workspace build, the second time with build/.../include
# newly on the compile line).
# @impl 0f87-6abe-8e68-a7a7
_create_fw_dirs:
	@mkdir -p ${.CURDIR}/${BINDIR_LOCAL} ${.CURDIR}/${LIBDIR_LOCAL} \
	          ${.CURDIR}/${SHAREDIR_LOCAL} ${.CURDIR}/${INCDIR_LOCAL}

# Aggregate resources (share/ overlay)
_aggregate:
	@# share/ 3-layer overlay: common → <os> → <os>_<arch>
	@if [ -d share/common ]; then \
		cp -a share/common/. ${.CURDIR}/${SHAREDIR_LOCAL}/ 2>/dev/null || true; \
	fi
	@if [ -d share/${TARGET} ]; then \
		cp -a share/${TARGET}/. ${.CURDIR}/${SHAREDIR_LOCAL}/ 2>/dev/null || true; \
	fi
	@if [ -d share/${TARGET}_${TARGET_ARCH} ]; then \
		cp -a share/${TARGET}_${TARGET_ARCH}/. ${.CURDIR}/${SHAREDIR_LOCAL}/ 2>/dev/null || true; \
	fi

# Copy framework outputs up to workspace
# @impl 0f87-6a98-8ee9-ae83
# _copy_up: the same copy without building first -- what the workspace asks
# for when only test modules failed (tst-failure-does-not-block-copy-up-req,
# mk.workspace.mk).
_FW_COPY_UP = _WS=${.CURDIR}/..; \
	sh ${BMK_MKDIR}/../scripts/diff-aware-copy.sh ${.CURDIR}/${BINDIR_LOCAL} $$_WS/${BINDIR_LOCAL}; \
	sh ${BMK_MKDIR}/../scripts/diff-aware-copy.sh ${.CURDIR}/${LIBDIR_LOCAL} $$_WS/${LIBDIR_LOCAL}; \
	sh ${BMK_MKDIR}/../scripts/diff-aware-copy.sh ${.CURDIR}/${SHAREDIR_LOCAL} $$_WS/${SHAREDIR_LOCAL}; \
	echo "===> framework ${.CURDIR:T} copy-up → workspace"
copy-up: all
	@${_FW_COPY_UP}
_copy_up:
	@${_FW_COPY_UP}

# leftover-module-dir-skipped-and-cleaned-req: a *.m/*.tst with no makefile
# cannot clean itself -- `make clean` inside it just failed, silently, and
# its build/ stayed. One holding only build output (bmk_is_leftover: e.g. a
# module removed by git switch, kept alive by its gitignored build/) is
# deleted; one holding anything else is reported and left alone.
# @impl 7854-6ad2-021e-2621
clean:
	@# modules: clean each *.m without relying on order generation
	@BMK_PROG=clean; . ${BMK_MKDIR}/../scripts/bmk-query.sh; \
	for _m in *.m *.tst; do \
		[ -d "$$_m" ] || continue; \
		if [ -f "$$_m/makefile" ]; then \
			${MAKE} -C "$$_m" clean \
				TARGET=${TARGET} TARGET_ARCH=${TARGET_ARCH} TOOLCHAIN=${TOOLCHAIN} \
				${ABI:DABI=${ABI}} BMK_MKDIR=${BMK_MKDIR} || true; \
		elif bmk_is_leftover "$$_m"; then \
			rm -rf "$$_m"; \
			echo "===> removed leftover $$_m (no makefile, only build output)"; \
		else \
			echo "warning: $$_m has no makefile but holds other files ($$(ls -A "$$_m" | tr '\n' ' ')) -- left untouched" >&2; \
		fi; \
	done
.if ${CLEAN_ALL_TARGETS} == "yes"
	rm -rf ${.CURDIR}/build ${.CURDIR}/distrib
	@# belt-and-suspenders: any nested build trees or gen files under this framework
	@find ${.CURDIR} -type d -name build -prune -exec rm -rf {} + 2>/dev/null || true
.else
	rm -rf ${.CURDIR}/${BUILD_ROOT} ${.CURDIR}/${DISTRIB_ROOT}
.endif
	rm -f ${.CURDIR}/.gen-mod-order.mk ${.CURDIR}/.gen-fw-order.mk ${.CURDIR}/.depend
	@find ${.CURDIR} -name '.gen-*.mk' -delete 2>/dev/null || true
# @impl 7854-6ad2-03bb-077e (clean-leaves-no-empty-build-dirs-req)
	@rmdir ${.CURDIR}/build ${.CURDIR}/distrib 2>/dev/null || true

# @impl 0f87-6a98-7918-e195
add-prereq:
.if !defined(FW) || empty(FW)
	@echo "usage: make add-prereq FW=<name>" >&2; exit 1
.endif
	@if grep -q '^PREREQS' makefile; then \
		sed -i.bak -e "s|^PREREQS=\\(.*\\)|PREREQS=\\1 ${FW}|" makefile; \
	else \
		echo "PREREQS=${FW}" >> makefile; \
	fi
	@echo "Appended ${FW} to PREREQS"

.PHONY: all clean help copy-up add-prereq _fw_test_build _fw_build_closure _fw_build_prereqs _create_fw_dirs _build_modules _aggregate _check_build_failures test _run_tests _check_test_failures

.include "${BMK_MKDIR}/mk.docs.mk"

_LOCAL_MK_PHASE = local
.include "${BMK_MKDIR}/mk.local.mk"

BMK_HELP_ROLE = framework
.include "${BMK_MKDIR}/mk.help.mk"

.else
_SK_ROLE = framework
.include "${BMK_MKDIR}/mk.skipped.mk"
.endif
.endif # _MK_FRAMEWORK_MK_
