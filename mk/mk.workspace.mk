# mk.workspace.mk — workspace role
# Usage:  PARENT_WS=/abs/path1 /abs/path2
#         .include <mk.workspace.mk>

.if !defined(_MK_WORKSPACE_MK_)
_MK_WORKSPACE_MK_ = 1

.if !defined(BMK_MKDIR)
.  if exists(${.PARSEDIR}/mk.common.mk)
BMK_MKDIR := ${.PARSEDIR}
.  elif exists(${.CURDIR}/mk/mk.common.mk)
BMK_MKDIR = ${.CURDIR}/mk
.  elif exists(${.CURDIR}/../mk/mk.common.mk)
BMK_MKDIR = ${.CURDIR}/../mk
.  else
BMK_MKDIR = ${.CURDIR}
.  endif
.endif

.include "${BMK_MKDIR}/mk.common.mk"

# PARENT_WS is optional; absolute paths only when present
.if defined(PARENT_WS) && !empty(PARENT_WS)
.  for _p in ${PARENT_WS}
.    if !exists(${_p})
.      warning "PARENT_WS entry does not exist: ${_p}"
.    endif
.  endfor
.endif

# ---------------------------------------------------------------------------
# Local customization hooks (local-mk-hook-files-and-cascade-order-req)
# Workspace level sees only its own mk/, extended to every PARENT_WS's mk/.
# PARENT_WS first (outermost/most general), own mk/ last (most specific --
# can override what a parent workspace set), matching the same outer-to-
# inner cascade principle used for WS -> FW -> MOD.
# ---------------------------------------------------------------------------
_LOCAL_MK_DIRS =
.for _p in ${PARENT_WS}
_LOCAL_MK_DIRS += ${_p}/mk
.endfor
_LOCAL_MK_DIRS += ${.CURDIR}/mk

_LOCAL_MK_PHASE = pre
.include "${BMK_MKDIR}/mk.local.mk"

# ---------------------------------------------------------------------------
# Auto-discover frameworks: subdirs containing makefile that defines PREREQS=
# ---------------------------------------------------------------------------
_GEN_FW = ${BMK_MKDIR}/../scripts/gen-fw-order.sh
_FW_ORDER_MK = ${.CURDIR}/.gen-fw-order.mk

.if exists(${_GEN_FW})
_fw_gen != cd ${.CURDIR} && BMK_MKDIR=${BMK_MKDIR} MAKESYSPATH=${BMK_MKDIR}:/usr/share/mk:/opt/local/share/mk sh ${_GEN_FW} ${_FW_ORDER_MK} 2>&1 || echo "FAILED"
.endif

.-include "${_FW_ORDER_MK}"
.if defined(FRAMEWORK_SUBDIR) && !empty(FRAMEWORK_SUBDIR)
SUBDIR_FRAMEWORKS := ${FRAMEWORK_SUBDIR}
.else
# Fallback discovery
_CANDIDATES != ls -d */makefile 2>/dev/null | sed 's|/makefile||' || true
SUBDIR_FRAMEWORKS =
.  for _c in ${_CANDIDATES}
.    if ${_c} != "build" && ${_c} != "distrib"
# @impl 0f87-6a98-77f0-fa5a
_has_prereqs != grep -l '^PREREQS' ${_c}/makefile 2>/dev/null || true
.      if !empty(_has_prereqs)
SUBDIR_FRAMEWORKS += ${_c}
.      endif
.    endif
.  endfor
.endif

# ---------------------------------------------------------------------------
# Default target: build all frameworks in PREREQS order, then aggregate.
# One framework's (or module's) build failure does NOT stop every other
# one from still being attempted, unless FAIL_FAST=yes. REPORT=yes
# additionally builds a workspace-level build-result dashboard
# (build-workspace-aggregation-req-v2) from whatever happened, under
# <BUILD_REPORT_DIR>/<RUN_ID>/<KEY>/ with a latest/<KEY>/ copy
# (run-history-not-overwritten-req). The <KEY> segment matters: two
# target keys (e.g. TOOLCHAIN=llvm and TOOLCHAIN=gcc) built under the
# same RUN_ID to correlate them as one CI pass must not overwrite each
# other's dashboard -- found and fixed 2026-09-16, the first version had
# exactly this collision.
# ---------------------------------------------------------------------------
BUILD_REPORT_DIR ?= build-report

all: _build_frameworks _aggregate_ws
	@echo "===> workspace build complete for ${OS_ARCH}"
.if ${REPORT} == "yes"
	@_rdir=${.CURDIR}/${BUILD_REPORT_DIR}/${RUN_ID}/${OS_ARCH}; mkdir -p "$$_rdir"
	@echo "<!DOCTYPE html><html><head><title>${.CURDIR:T} build dashboard</title>" > ${.CURDIR}/${BUILD_REPORT_DIR}/${RUN_ID}/${OS_ARCH}/index.html
	@echo "<style>body{font-family:sans-serif}table{border-collapse:collapse}td,th{border:1px solid #ccc;padding:6px 10px;text-align:left}.fail{color:#b00;font-weight:bold}.pass{color:#080}</style></head><body>" >> ${.CURDIR}/${BUILD_REPORT_DIR}/${RUN_ID}/${OS_ARCH}/index.html
	@echo "<h1>${.CURDIR:T} build dashboard <small>${RUN_ID} / ${OS_ARCH}</small></h1>" >> ${.CURDIR}/${BUILD_REPORT_DIR}/${RUN_ID}/${OS_ARCH}/index.html
	@echo "<table><tr><th>Framework</th><th>Module</th><th>Result</th><th>Log</th></tr>" >> ${.CURDIR}/${BUILD_REPORT_DIR}/${RUN_ID}/${OS_ARCH}/index.html
	@_total_fail=0; _total_pass=0; \
	for _f in ${SUBDIR_FRAMEWORKS}; do \
		_mods=$$(${MAKE} -C $$_f -V SUBDIR_MODULES 2>/dev/null); \
		for _m in $$_mods; do \
			_log=$$_f/$$_m/${BUILD_ROOT}/runs/${RUN_ID}/build.log; \
			[ -f "$$_log" ] || continue; \
			if [ -f "$$_f/$$_m/${BUILD_ROOT}/runs/${RUN_ID}/build.failed" ]; then \
				_status="<span class=\"fail\">FAIL</span>"; _total_fail=$$((_total_fail+1)); \
			else \
				_status="<span class=\"pass\">PASS</span>"; _total_pass=$$((_total_pass+1)); \
			fi; \
			echo "<tr><td>$$_f</td><td>$$_m</td><td>$$_status</td><td><a href=\"../../../$$_log\">build.log</a></td></tr>" \
				>> ${.CURDIR}/${BUILD_REPORT_DIR}/${RUN_ID}/${OS_ARCH}/index.html; \
		done; \
	done; \
	echo "</table><p>$$_total_pass module(s) built clean, $$_total_fail module(s) failed.</p>" \
		>> ${.CURDIR}/${BUILD_REPORT_DIR}/${RUN_ID}/${OS_ARCH}/index.html
	@echo "</body></html>" >> ${.CURDIR}/${BUILD_REPORT_DIR}/${RUN_ID}/${OS_ARCH}/index.html
	@rm -rf ${.CURDIR}/${BUILD_REPORT_DIR}/latest/${OS_ARCH}; mkdir -p ${.CURDIR}/${BUILD_REPORT_DIR}/latest
	@cp -a ${.CURDIR}/${BUILD_REPORT_DIR}/${RUN_ID}/${OS_ARCH} ${.CURDIR}/${BUILD_REPORT_DIR}/latest/${OS_ARCH}
	@echo "===> workspace build dashboard -> ${BUILD_REPORT_DIR}/${RUN_ID}/${OS_ARCH}/index.html (also ${BUILD_REPORT_DIR}/latest/${OS_ARCH}/)"
.endif

.if !defined(SUBDIR_FRAMEWORKS)
SUBDIR_FRAMEWORKS := ${FRAMEWORK_SUBDIR}
.endif

# Each framework's build output is always captured to a rollup log at
# <framework>/<BUILD_ROOT>/runs/<RUN_ID>/build.log (tee'd, so console
# output is unchanged; runs/latest kept pointing at it) -- it already
# contains every one of that framework's own modules' individually-
# logged output, since that's what streamed to stdout/stderr during the
# framework's own recursive build. One framework's failure does NOT stop
# every other one from still being attempted, unless FAIL_FAST=yes
# (build-workspace-aggregation-req-v2, run-history-not-overwritten-req).
# @impl 0f87-6a98-5e47-0c71
# @impl 0f87-6aaa-6a6e-00d0
# @impl 0f87-6aaa-72d2-8ffc
_build_frameworks:
.for _f in ${SUBDIR_FRAMEWORKS}
	@echo "===> building framework ${_f}"
	@_rundir=${.CURDIR}/${_f}/${BUILD_ROOT}/runs/${RUN_ID}; mkdir -p "$$_rundir"; \
	_rcfile=$$(mktemp); \
	{ ${MAKE} -C ${_f} all \
		TARGET=${TARGET} TARGET_ARCH=${TARGET_ARCH} TOOLCHAIN=${TOOLCHAIN} \
		BMK_MKDIR=${BMK_MKDIR} PARENT_WS="${PARENT_WS}" SANITIZE="${SANITIZE}" REPORT="${REPORT}" FAIL_FAST="${FAIL_FAST}" RUN_ID="${RUN_ID}"; \
	  echo $$? > "$$_rcfile"; } 2>&1 | tee "$$_rundir/build.log"; \
	_rc=$$(cat "$$_rcfile"); rm -f "$$_rcfile"; \
	if [ "$$_rc" -eq 0 ]; then \
		rm -f "$$_rundir/build.failed"; \
		${MAKE} -C ${_f} copy-up \
			TARGET=${TARGET} TARGET_ARCH=${TARGET_ARCH} TOOLCHAIN=${TOOLCHAIN} \
			BMK_MKDIR=${BMK_MKDIR} PARENT_WS="${PARENT_WS}" SANITIZE="${SANITIZE}" FAIL_FAST="${FAIL_FAST}" RUN_ID="${RUN_ID}" \
			2>&1 | tee -a "$$_rundir/build.log"; \
	else \
		touch "$$_rundir/build.failed"; \
		echo "===> framework ${_f} build FAILED -- see ${_f}/${BUILD_ROOT}/runs/${RUN_ID}/build.log" >&2; \
		if [ "${FAIL_FAST}" = "yes" ]; then exit 1; fi; \
	fi; \
	rm -rf ${.CURDIR}/${_f}/${BUILD_ROOT}/runs/latest; \
	cp -a "$$_rundir" ${.CURDIR}/${_f}/${BUILD_ROOT}/runs/latest
.endfor

_aggregate_ws:
	@mkdir -p ${.CURDIR}/${BINDIR_LOCAL} ${.CURDIR}/${LIBDIR_LOCAL} \
	          ${.CURDIR}/${SHAREDIR_LOCAL}

# @impl 0f87-6aaa-6a6e-00d0
clean:
	@# frameworks: recurse without depending on generated order file
	@for _f in */makefile; do \
		[ -f "$$_f" ] || continue; \
		_d=$$(dirname "$$_f"); \
		case "$$_d" in build|distrib) continue ;; esac; \
		grep -q '^PREREQS' "$$_f" 2>/dev/null || continue; \
		${MAKE} -C "$$_d" clean \
			TARGET=${TARGET} TARGET_ARCH=${TARGET_ARCH} TOOLCHAIN=${TOOLCHAIN} \
			BMK_MKDIR=${BMK_MKDIR} || true; \
	done
.if ${CLEAN_ALL_TARGETS} == "yes"
	rm -rf ${.CURDIR}/build ${.CURDIR}/distrib ${.CURDIR}/${BUILD_REPORT_DIR} ${.CURDIR}/${TEST_REPORT_DIR}
	@# full source-only slate: any leftover build/ or generated order files
	@find ${.CURDIR} \( -type d -name build -o -type d -name distrib \) -prune -exec rm -rf {} + 2>/dev/null || true
.else
	rm -rf ${.CURDIR}/${BUILD_ROOT} ${.CURDIR}/${DISTRIB_ROOT}
	@# dashboards are keyed by <RUN_ID-or-latest>/<KEY>/ -- remove just
	@# this target key's data across every run (run-history-not-
	@# overwritten-req), leaving other target keys' history alone, then
	@# prune any run/latest dirs left empty by that removal.
	@for _d in ${.CURDIR}/${BUILD_REPORT_DIR} ${.CURDIR}/${TEST_REPORT_DIR}; do \
		[ -d "$$_d" ] || continue; \
		find "$$_d" -mindepth 2 -maxdepth 2 -type d -name '${OS_ARCH}' -exec rm -rf {} + 2>/dev/null; \
		find "$$_d" -mindepth 1 -maxdepth 1 -type d -empty -delete 2>/dev/null; \
	done
.endif
	rm -f ${.CURDIR}/.gen-fw-order.mk ${.CURDIR}/.gen-mod-order.mk ${.CURDIR}/.depend
	@find ${.CURDIR} -name '.gen-*.mk' -delete 2>/dev/null || true
	@find ${.CURDIR} -name '.depend' -delete 2>/dev/null || true

# Convenience targets (REQ-add-prereq-add-parent-convenience-targets-req)
# @impl 0f87-6a98-7918-e195
add-parent:
.if !defined(WS) || empty(WS)
	@echo "usage: make add-parent WS=/absolute/path" >&2; exit 1
.endif
	@if grep -q '^PARENT_WS' makefile; then \
		sed -i.bak -e "s|^PARENT_WS=\\(.*\\)|PARENT_WS=\\1 ${WS}|" makefile; \
	else \
		echo "PARENT_WS=${WS}" >> makefile; \
	fi
	@echo "Appended ${WS} to PARENT_WS"

# @impl 0f87-6a98-7755-574e
install:
	@echo "install: use DESTDIR= and PREFIX= (PREFIX is project-level)"
	@# Requires pre-built target
	@if [ ! -d ${BUILD_ROOT} ]; then \
		echo "error: ${BUILD_ROOT} does not exist — build first" >&2; exit 1; \
	fi
	@DEST=${DESTDIR}${PREFIX:U/usr/local}; \
	mkdir -p $$DEST/bin $$DEST/lib $$DEST/share; \
	cp -a ${BINDIR_LOCAL}/. $$DEST/bin/ 2>/dev/null || true; \
	cp -a ${LIBDIR_LOCAL}/. $$DEST/lib/ 2>/dev/null || true; \
	cp -a ${SHAREDIR_LOCAL}/. $$DEST/share/ 2>/dev/null || true; \
	echo "===> installed to $$DEST"

# run: convenience target — defined in mk.common.mk (shared across all
# roles) so it also works from a framework/module directory, not just here.

# docs: generate every framework's own docs (PREREQS order, so a
# dependent's tag-file cross-links resolve), then a landing page linking
# each framework's own docs/html/index.html. The landing page gets the
# same project-metadata treatment as each framework's own Doxygen page
# (name/version/brief/logo/license), read from the workspace root -- the
# canonical source frameworks inherit from when they don't override it.
# @impl 0f87-6aa9-0267-bd7c
DOCS_DIR ?= docs
DOC_PROJECT_NAME ?= ${.CURDIR:T}
DOC_PROJECT_BRIEF ?=

.if !defined(DOC_PROJECT_VERSION)
.  if exists(${.CURDIR}/VERSION)
DOC_PROJECT_VERSION != cat ${.CURDIR}/VERSION 2>/dev/null | head -1
.  else
DOC_PROJECT_VERSION =
.  endif
.endif

.if !defined(DOC_LOGO)
.  if exists(${.CURDIR}/${DOCS_DIR}/logo.png)
DOC_LOGO = ${.CURDIR}/${DOCS_DIR}/logo.png
.  elif exists(${.CURDIR}/${DOCS_DIR}/logo.svg)
DOC_LOGO = ${.CURDIR}/${DOCS_DIR}/logo.svg
.  else
DOC_LOGO =
.  endif
.endif

.if !defined(DOC_LICENSE_NOTICE)
.  if exists(${.CURDIR}/LICENSE)
DOC_LICENSE_NOTICE != head -1 ${.CURDIR}/LICENSE 2>/dev/null
.  else
DOC_LICENSE_NOTICE =
.  endif
.endif

docs:
.for _f in ${SUBDIR_FRAMEWORKS}
	@${MAKE} -C ${_f} docs BMK_MKDIR=${BMK_MKDIR}
.endfor
	@mkdir -p ${.CURDIR}/${DOCS_DIR}
	@echo "<!DOCTYPE html><html><head><title>${DOC_PROJECT_NAME}</title></head><body>" > ${.CURDIR}/${DOCS_DIR}/index.html
.if !empty(DOC_LOGO)
	@echo "<img src=\"${DOC_LOGO:T}\" alt=\"logo\" height=\"64\">" >> ${.CURDIR}/${DOCS_DIR}/index.html
	@if [ "${DOC_LOGO}" != "${.CURDIR}/${DOCS_DIR}/${DOC_LOGO:T}" ]; then \
		cp ${DOC_LOGO} ${.CURDIR}/${DOCS_DIR}/${DOC_LOGO:T}; \
	fi
.endif
	@echo "<h1>${DOC_PROJECT_NAME}" >> ${.CURDIR}/${DOCS_DIR}/index.html
.if !empty(DOC_PROJECT_VERSION)
	@echo " <small>${DOC_PROJECT_VERSION}</small>" >> ${.CURDIR}/${DOCS_DIR}/index.html
.endif
	@echo "</h1>" >> ${.CURDIR}/${DOCS_DIR}/index.html
.if !empty(DOC_PROJECT_BRIEF)
	@echo "<p>${DOC_PROJECT_BRIEF}</p>" >> ${.CURDIR}/${DOCS_DIR}/index.html
.endif
	@echo "<ul>" >> ${.CURDIR}/${DOCS_DIR}/index.html
.for _f in ${SUBDIR_FRAMEWORKS}
	@echo "<li><a href=\"../${_f}/${DOCS_DIR}/html/index.html\">${_f}</a></li>" >> ${.CURDIR}/${DOCS_DIR}/index.html
.endfor
	@echo "</ul>" >> ${.CURDIR}/${DOCS_DIR}/index.html
.if !empty(DOC_LICENSE_NOTICE)
	@echo "<p><small>${DOC_LICENSE_NOTICE}</small></p>" >> ${.CURDIR}/${DOCS_DIR}/index.html
.endif
	@echo "</body></html>" >> ${.CURDIR}/${DOCS_DIR}/index.html
	@echo "===> workspace docs complete -> ${DOCS_DIR}/index.html"

TEST_REPORT_DIR ?= test-report

# test: recurse into every framework (or just FW=<name>, if given), which
# recurses into every module (or just the one declaring TEST=<name>, if
# given) -- test-workspace-aggregation-req. REPORT=yes additionally
# builds a workspace-level dashboard under test-report/<RUN_ID>/ (with a
# test-report/latest symlink) linking every module's own report for that
# same RUN_ID; the dashboard scan respects the same FW=/TEST=/RUN_ID
# scoping as the run itself, so a filtered or later run doesn't surface
# stale results from a different run or a module it didn't touch this
# time (run-history-not-overwritten-req). Existence-based, not a static
# TESTS_* scan: mk.test.mk's no-tests branch never creates
# test-report-html/, so walking for that directory after the run is
# simpler and more accurate than re-deriving which modules declare
# tests. Each framework's own module list is queried the same way
# mk.lib.mk queries a prereq framework's PREREQS= (a plain -V query, no
# TARGET/TOOLCHAIN needed -- module discovery doesn't depend on either).
# @impl 0f87-6aaa-6201-a430
# @impl 0f87-6aaa-697c-4c30
# @impl 0f87-6aaa-72d2-8ffc
test:
.for _f in ${SUBDIR_FRAMEWORKS}
	@if [ -z "${FW}" ] || [ "${_f}" = "${FW}" ]; then \
		${MAKE} -C ${_f} test \
			TARGET=${TARGET} TARGET_ARCH=${TARGET_ARCH} TOOLCHAIN=${TOOLCHAIN} \
			BMK_MKDIR=${BMK_MKDIR} PARENT_WS="${PARENT_WS}" SANITIZE="${SANITIZE}" FAIL_FAST="${FAIL_FAST}" \
			REPORT="${REPORT}" TEST="${TEST}" RUN_ID="${RUN_ID}"; \
		_trc=$$?; \
		if [ "$$_trc" -ne 0 ] && [ "${FAIL_FAST}" = "yes" ]; then exit $$_trc; fi; \
	fi
.endfor
.if ${REPORT} == "yes"
	@mkdir -p ${.CURDIR}/${TEST_REPORT_DIR}/${RUN_ID}/${OS_ARCH}
	@echo "<!DOCTYPE html><html><head><title>${.CURDIR:T} test dashboard</title>" > ${.CURDIR}/${TEST_REPORT_DIR}/${RUN_ID}/${OS_ARCH}/index.html
	@echo "<style>body{font-family:sans-serif}table{border-collapse:collapse}td,th{border:1px solid #ccc;padding:6px 10px;text-align:left}.fail{color:#b00;font-weight:bold}.pass{color:#080}</style></head><body>" >> ${.CURDIR}/${TEST_REPORT_DIR}/${RUN_ID}/${OS_ARCH}/index.html
	@echo "<h1>${.CURDIR:T} test dashboard <small>${RUN_ID} / ${OS_ARCH}</small></h1>" >> ${.CURDIR}/${TEST_REPORT_DIR}/${RUN_ID}/${OS_ARCH}/index.html
	@echo "<table><tr><th>Framework</th><th>Module</th><th>Result</th><th>Reports</th></tr>" >> ${.CURDIR}/${TEST_REPORT_DIR}/${RUN_ID}/${OS_ARCH}/index.html
	@_total_fail=0; _total_pass=0; \
	for _f in ${SUBDIR_FRAMEWORKS}; do \
		[ -z "${FW}" ] || [ "$$_f" = "${FW}" ] || continue; \
		_mods=$$(${MAKE} -C $$_f -V SUBDIR_MODULES 2>/dev/null); \
		for _m in $$_mods; do \
			if [ -n "${TEST}" ]; then \
				_has=$$(${MAKE} -C $$_f/$$_m -V '$${TESTS_CXX} $${TESTS_C} $${TESTS_SH}' 2>/dev/null); \
				case " $$_has " in *" ${TEST} "*) ;; *) continue ;; esac; \
			fi; \
			_html=$$_f/$$_m/${BUILD_ROOT}/runs/${RUN_ID}/test-report-html/index.html; \
			_xml=$$_f/$$_m/${BUILD_ROOT}/runs/${RUN_ID}/test-results.xml; \
			[ -f "$$_html" ] || continue; \
			_fails=$$(grep -cE '<(failure|error)' "$$_xml" 2>/dev/null); \
			_fails=$${_fails:-0}; \
			if [ "$$_fails" -gt 0 ]; then \
				_status="<span class=\"fail\">FAIL ($$_fails)</span>"; _total_fail=$$((_total_fail+1)); \
			else \
				_status="<span class=\"pass\">PASS</span>"; _total_pass=$$((_total_pass+1)); \
			fi; \
			echo "<tr><td>$$_f</td><td>$$_m</td><td>$$_status</td><td><a href=\"../../../$$_html\">HTML</a> / <a href=\"../../../$$_xml\">JUnit XML</a></td></tr>" \
				>> ${.CURDIR}/${TEST_REPORT_DIR}/${RUN_ID}/${OS_ARCH}/index.html; \
		done; \
	done; \
	echo "</table><p>$$_total_pass module(s) clean, $$_total_fail module(s) with failures.</p>" \
		>> ${.CURDIR}/${TEST_REPORT_DIR}/${RUN_ID}/${OS_ARCH}/index.html
	@echo "</body></html>" >> ${.CURDIR}/${TEST_REPORT_DIR}/${RUN_ID}/${OS_ARCH}/index.html
	@rm -rf ${.CURDIR}/${TEST_REPORT_DIR}/latest/${OS_ARCH}; mkdir -p ${.CURDIR}/${TEST_REPORT_DIR}/latest
	@cp -a ${.CURDIR}/${TEST_REPORT_DIR}/${RUN_ID}/${OS_ARCH} ${.CURDIR}/${TEST_REPORT_DIR}/latest/${OS_ARCH}
	@echo "===> workspace test dashboard -> ${TEST_REPORT_DIR}/${RUN_ID}/${OS_ARCH}/index.html (also ${TEST_REPORT_DIR}/latest/${OS_ARCH}/)"
.endif

.PHONY: all clean help _build_frameworks _aggregate_ws add-parent install docs test

_LOCAL_MK_PHASE = local
.include "${BMK_MKDIR}/mk.local.mk"

BMK_HELP_ROLE = workspace
.include "${BMK_MKDIR}/mk.help.mk"

.endif # _MK_WORKSPACE_MK_
