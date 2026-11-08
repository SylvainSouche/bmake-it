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
.  for _p in ${_PARENT_WS_E}
.    if !exists(${_p:${_BMK_DEC}})
.      warning "PARENT_WS entry does not exist: ${_p:${_BMK_DEC}}"
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
.for _p in ${_PARENT_WS_E}
_LOCAL_MK_DIRS += ${_p}/mk
.endfor
_LOCAL_MK_DIRS += ${.CURDIR:${_BMK_ENCW}}/mk

_LOCAL_MK_PHASE = pre
.include "${BMK_MKDIR}/mk.local.mk"
.include "${BMK_MKDIR}/mk.resolved.mk"

# ---------------------------------------------------------------------------
# Auto-discover frameworks: subdirs containing makefile that defines PREREQS=
# ---------------------------------------------------------------------------
_GEN_FW = ${BMK_MKDIR}/../scripts/gen-fw-order.sh
_FW_ORDER_MK = ${.CURDIR}/.gen-fw-order.mk

.if exists(${_GEN_FW})
# order-query-sys-mk-located-req: the nested PREREQS= queries look for
# sys.mk where THIS bmake found it (.SYSPATH) before any hardcoded list --
# a hardcoded /usr/share/mk:/opt/local/share/mk here missed Cygwin's
# /usr/share/bmake/mk and overrode the user's own, correct MAKESYSPATH.
# @impl 7854-6ad0-c2da-f4ce
# order-query-failure-is-error-req: stderr is NOT captured, so the
# generator's own explanation reaches the terminal as written; a failure
# stops the build here rather than falling back to discovery order.
# @impl 7854-6ad0-c2da-1218
_fw_gen != cd ${.CURDIR:Q} && BMK_MKDIR=${BMK_MKDIR:Q} MAKESYSPATH=${BMK_MKDIR:Q}:${.SYSPATH:U:ts::Q} BMK_SYS_MK=${BMK_SYS_MK:U:Q} BMAKE=${MAKE:Q} sh ${_GEN_FW:Q} ${_FW_ORDER_MK:Q} || echo "FAILED:$$?"
# order-failure-in-query-is-warning-req: a -V query still answers (as for
# REQUIRES=/constraint errors); only a build stops.
# @impl 7854-6ad0-c7d9-13f6
.  if !empty(_fw_gen:MFAILED*)
.    if empty(.MAKEFLAGS:M-V*) && !make(clean)
.      error framework build order could not be determined (scripts/gen-fw-order.sh failed, its reason is printed above)
.    else
.      warning framework build order could not be determined (scripts/gen-fw-order.sh failed, its reason is printed above); a build here will stop on it
.    endif
.  endif
.endif

.-include "${_FW_ORDER_MK}"
.if defined(FRAMEWORK_SUBDIR) && !empty(FRAMEWORK_SUBDIR)
SUBDIR_FRAMEWORKS := ${FRAMEWORK_SUBDIR}
.else
# Fallback discovery
_CANDIDATES != . ${BMK_MKDIR:Q}/../scripts/bmk-names.sh; for _c in */makefile; do [ -f "$$_c" ] && bmk_enc "$${_c%/makefile}"; done; true
SUBDIR_FRAMEWORKS =
.  for _c in ${_CANDIDATES}
.    if ${_c} != "build" && ${_c} != "distrib"
# @impl 0f87-6a98-77f0-fa5a
_has_prereqs != grep -l '^PREREQS' ${_c:${_BMK_DEC}:Q}/makefile 2>/dev/null || true
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

all: _requires_preflight _build_frameworks _aggregate_ws
.if ${REPORT} == "yes"
	@_rdir=${.CURDIR:Q}/${BUILD_REPORT_DIR:Q}/${RUN_ID}/${OS_ARCH}; mkdir -p "$$_rdir"
	@echo "<!DOCTYPE html><html><head><title>${_CURNAME} build dashboard</title>" > ${.CURDIR:Q}/${BUILD_REPORT_DIR:Q}/${RUN_ID}/${OS_ARCH}/index.html
	@echo "<style>body{font-family:sans-serif}table{border-collapse:collapse}td,th{border:1px solid #ccc;padding:6px 10px;text-align:left}.fail{color:#b00;font-weight:bold}.pass{color:#080}</style></head><body>" >> ${.CURDIR:Q}/${BUILD_REPORT_DIR:Q}/${RUN_ID}/${OS_ARCH}/index.html
	@echo "<h1>${_CURNAME} build dashboard <small>${RUN_ID} / ${OS_ARCH}</small></h1>" >> ${.CURDIR:Q}/${BUILD_REPORT_DIR:Q}/${RUN_ID}/${OS_ARCH}/index.html
	@echo "<table><tr><th>Framework</th><th>Module</th><th>Result</th><th>Log</th></tr>" >> ${.CURDIR:Q}/${BUILD_REPORT_DIR:Q}/${RUN_ID}/${OS_ARCH}/index.html
	@. ${BMK_MKDIR:Q}/../scripts/bmk-names.sh; \
	_total_fail=0; _total_pass=0; \
	for _fw in ${SUBDIR_FRAMEWORKS}; do \
		_f=$$(bmk_dec "$$_fw"); \
		for _mw in $$(${MAKE} -C "$$_f" -V SUBDIR_MODULES 2>/dev/null); do \
			_m=$$(bmk_dec "$$_mw"); \
			_log="$$_f/$$_m/${BUILD_ROOT}/runs/${RUN_ID}/build.log"; \
			[ -f "$$_log" ] || continue; \
			if [ -f "$$_f/$$_m/${BUILD_ROOT}/runs/${RUN_ID}/build.failed" ]; then \
				_status="<span class=\"fail\">FAIL</span>"; _total_fail=$$((_total_fail+1)); \
			else \
				_status="<span class=\"pass\">PASS</span>"; _total_pass=$$((_total_pass+1)); \
			fi; \
			echo "<tr><td>$$_f</td><td>$$_m</td><td>$$_status</td><td><a href=\"../../../$$_log\">build.log</a></td></tr>" \
				>> ${.CURDIR:Q}/${BUILD_REPORT_DIR:Q}/${RUN_ID}/${OS_ARCH}/index.html; \
		done; \
	done; \
	echo "</table><p>$$_total_pass module(s) built clean, $$_total_fail module(s) failed.</p>" \
		>> ${.CURDIR:Q}/${BUILD_REPORT_DIR:Q}/${RUN_ID}/${OS_ARCH}/index.html
	@echo "</body></html>" >> ${.CURDIR:Q}/${BUILD_REPORT_DIR:Q}/${RUN_ID}/${OS_ARCH}/index.html
	@rm -rf ${.CURDIR:Q}/${BUILD_REPORT_DIR:Q}/latest/${OS_ARCH}; mkdir -p ${.CURDIR:Q}/${BUILD_REPORT_DIR:Q}/latest
	@cp -a ${.CURDIR:Q}/${BUILD_REPORT_DIR:Q}/${RUN_ID}/${OS_ARCH} ${.CURDIR:Q}/${BUILD_REPORT_DIR:Q}/latest/${OS_ARCH}
	@echo "===> workspace build dashboard -> ${BUILD_REPORT_DIR}/${RUN_ID}/${OS_ARCH}/index.html (also ${BUILD_REPORT_DIR}/latest/${OS_ARCH}/)"
.endif
	@# aggregation-failure-exit-code-req: runs last, after the REPORT=yes
	@# dashboard above (if any) so it's generated regardless -- this is
	@# purely about the workspace `all`'s own final exit code. Each
	@# framework's own build.failed marker is now reliable in turn: its
	@# `all` recursion (mk.framework.mk's own _check_build_failures)
	@# correctly fails when any of ITS modules failed.
	@# @impl 0f87-6ab5-81a2-7bb0
	@. ${BMK_MKDIR:Q}/../scripts/bmk-names.sh; \
	_failed=""; _skipped=""; \
	for _fw in ${SUBDIR_FRAMEWORKS}; do \
		_f=$$(bmk_dec "$$_fw"); \
		_rd=${.CURDIR:Q}/"$$_f/${BUILD_ROOT}/runs/${RUN_ID}"; \
		if [ -f "$$_rd/build.skipped" ]; then \
			_skipped="$$_skipped $$_fw"; \
		elif [ -f "$$_rd/build.failed" ]; then \
			_failed="$$_failed $$_fw"; \
		fi; \
	done; \
	if [ -n "$$_failed$$_skipped" ]; then \
		echo "===> workspace BUILD FAILED:$$(for _fw in $$_failed $$_skipped; do printf ' %s' "$$(bmk_dec "$$_fw")"; done)" >&2; \
		for _fw in $$_failed; do \
			_f=$$(bmk_dec "$$_fw"); \
			echo "     $$_f -- see $$_f/${BUILD_ROOT}/runs/${RUN_ID}/build.log" >&2; \
		done; \
		for _fw in $$_skipped; do \
			_f=$$(bmk_dec "$$_fw"); \
			echo "     $$_f -- skipped, root cause: $$(cat ${.CURDIR:Q}/"$$_f/${BUILD_ROOT}/runs/${RUN_ID}/build.skipped")" >&2; \
		done; \
		exit 1; \
	fi
	@# (only now: it said "complete" right before "BUILD FAILED")
	@echo "===> workspace build complete for ${OS_ARCH}"

# requires-preflight-req: every framework's modules are asked what they lack
# (mk.framework.mk _check_requires) before any framework is built; anything
# missing is printed as one list and nothing is built.
# @impl 7854-6ae3-0b4f-513f
_requires_preflight:
.if ${BMK_REQUIRES_CHECKED:U} != "yes"
	@. ${BMK_MKDIR:Q}/../scripts/bmk-names.sh; \
	_list=$$(mktemp); \
	for _fw in ${SUBDIR_FRAMEWORKS}; do \
		_f=$$(bmk_dec "$$_fw"); \
		${MAKE} -C ${.CURDIR:Q}/"$$_f" _check_requires BMK_REQUIRES_LIST="$$_list" \
			BMK_REQUIRES_FOR="${BMK_REQUIRES_FOR:U${.TARGETS}}" \
			TARGET=${TARGET} TARGET_ARCH=${TARGET_ARCH} TOOLCHAIN=${TOOLCHAIN} \
			BMK_MKDIR=${BMK_MKDIR:Q} PARENT_WS="${PARENT_WS}" || { rm -f "$$_list"; exit 1; }; \
	done; \
	_rc=0; sh ${BMK_MKDIR:Q}/../scripts/requires-report.sh "$$_list" || _rc=$$?; rm -f "$$_list"; exit $$_rc
.else
	@:
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
# failed-prereq-framework-skip-req: a framework whose PREREQS= names a
# framework that failed (or was itself skipped) is not built -- it would
# only fail again, much later and far noisier (found in real use: a
# REQUIRES= failure in GIS was followed by Geo/Viewer dying on a missing
# glm header ~450 lines on). One line says why; the root cause is carried
# along (build.skipped) so a transitive skip can name it. Independent
# frameworks are still attempted (keep-going); the skipped one is marked
# build.failed so the exit status stays non-zero. PREREQS= is only
# queried once something has already failed, so a healthy build pays
# nothing.
# single-module-visit-req: `all copy-up` is ONE make invocation per
# framework, not two (the second re-entered every module just to find
# nothing to do).
# @impl 0f87-6abf-aeba-66f1
# @impl 0f87-6abf-aeba-b9eb
# tst-failure-does-not-block-copy-up-req: a framework whose only failed
# modules are .tst ones is still copied up (_copy_up, no rebuild), says so,
# and does not get its dependents skipped (build.testsonly); the build
# still fails. A test that did not link kept OpenRider's own program out of
# the workspace, so `run` could not find it (FreeBSD, 2026-10-29).
# @impl 7854-6ae3-3af2-b095
# recipe-paths-quoted-req: every directory below is written for the shell (:Q), and a
# framework name is decoded from its word once, into _fn, and used quoted.
# @impl 0f87-6af0-c379-1630
_build_frameworks:
.for _f in ${SUBDIR_FRAMEWORKS}
	@. ${BMK_MKDIR:Q}/../scripts/bmk-names.sh; \
	_fn=${_f:${_BMK_DEC}:Q}; _ws=${.CURDIR:Q}; \
	_rundir="$$_ws/$$_fn/${BUILD_ROOT}/runs/${RUN_ID}"; mkdir -p "$$_rundir"; \
	_why=""; _root=""; _excl=""; _anyfail=no; \
	for _xw in ${SUBDIR_FRAMEWORKS}; do \
		_x=$$(bmk_dec "$$_xw"); \
		[ "$$_x" = "$$_fn" ] && break; \
		[ -f "$$_ws/$$_x/${BUILD_ROOT}/runs/${RUN_ID}/build.failed" ] && _anyfail=yes; \
		[ -f "$$_ws/$$_x/${BUILD_ROOT}/runs/${RUN_ID}/build.excluded" ] && _anyfail=yes; \
	done; \
	if [ "$$_anyfail" = yes ]; then \
		for _pw in $$(${MAKE} -C "$$_fn" -V '$${_PREREQS_E}' 2>/dev/null); do \
			_p=$$(bmk_dec "$$_pw"); \
			_pd="$$_ws/$$_p/${BUILD_ROOT}/runs/${RUN_ID}"; \
			if [ -f "$$_pd/build.failed" ] && [ ! -f "$$_pd/build.testsonly" ]; then \
				_why=$$_p; \
				if [ -f "$$_pd/build.skipped" ]; then _root=$$(cat "$$_pd/build.skipped"); else _root=$$_p; fi; \
				break; \
			elif [ -f "$$_pd/build.excluded" ] && [ -z "$$_excl" ]; then \
				if [ "$$(${MAKE} -C "$$_fn" -V _BMK_BUILD 2>/dev/null)" != skip ]; then _excl=$$_p; fi; \
			fi; \
		done; \
	fi; \
	if [ -n "$$_excl" ] && [ -z "$$_why" ]; then \
		_msg="===> framework $$_fn cannot be built: it needs $$_excl, which is not built here ($$(cat "$$_ws/$$_excl/${BUILD_ROOT}/runs/${RUN_ID}/build.excluded")) -- give $$_fn the same PLATFORMS=/TOOLCHAINS="; \
		echo "$$_msg" >&2; echo "$$_msg" > "$$_rundir/build.log"; \
		touch "$$_rundir/build.failed"; \
		if [ "${FAIL_FAST}" = "yes" ]; then exit 1; fi; \
	elif [ -n "$$_why" ]; then \
		_msg="===> framework $$_fn skipped: prerequisite $$_why failed"; \
		if [ "$$_root" != "$$_why" ]; then _msg="$$_msg (root cause: $$_root)"; fi; \
		echo "$$_msg" >&2; echo "$$_msg" > "$$_rundir/build.log"; \
		echo "$$_root" > "$$_rundir/build.skipped"; touch "$$_rundir/build.failed"; \
		if [ "${FAIL_FAST}" = "yes" ]; then exit 1; fi; \
	else \
		rm -f "$$_rundir/build.skipped"; \
		echo "===> building framework $$_fn"; \
		_rcfile=$$(mktemp); \
		{ ${MAKE} -C "$$_fn" all copy-up \
			TARGET=${TARGET} TARGET_ARCH=${TARGET_ARCH} TOOLCHAIN=${TOOLCHAIN} \
			BMK_MKDIR=${BMK_MKDIR:Q} PARENT_WS="${PARENT_WS}" SANITIZE="${SANITIZE}" REPORT="${REPORT}" FAIL_FAST="${FAIL_FAST}" RUN_ID="${RUN_ID}" \
			BMK_REQUIRES_CHECKED=yes \
		  && echo 0 > "$$_rcfile" || echo $$? > "$$_rcfile"; } 2>&1 | tee "$$_rundir/build.log"; \
		_rc=$$(cat "$$_rcfile"); rm -f "$$_rcfile"; \
		if [ "$$_rc" -eq 0 ]; then \
			rm -f "$$_rundir/build.failed"; \
		else \
			touch "$$_rundir/build.failed"; rm -f "$$_rundir/build.testsonly"; \
			_tf=""; _mf=""; \
			for _m in "$$_ws/$$_fn"/*.m "$$_ws/$$_fn"/*.tst; do \
				if [ -f "$$_m/${BUILD_ROOT}/runs/${RUN_ID}/build.failed" ]; then \
					case "$$_m" in *.tst) _tf="$$_tf $$(bmk_enc "$${_m##*/}")" ;; *) _mf="$$_mf $$(bmk_enc "$${_m##*/}")" ;; esac; \
				fi; \
			done; \
			if [ -n "$$_tf" ] && [ -z "$$_mf" ] && ${MAKE} -C "$$_fn" _copy_up \
				TARGET=${TARGET} TARGET_ARCH=${TARGET_ARCH} TOOLCHAIN=${TOOLCHAIN} BMK_MKDIR=${BMK_MKDIR:Q} >/dev/null; then \
				touch "$$_rundir/build.testsonly"; \
				echo "===> framework $$_fn: only test modules failed ($$(for _t in $$_tf; do printf '%s ' "$$(bmk_dec "$$_t")"; done | sed 's/ $$//')) -- its programs and libraries are copied up all the same" >&2; \
			fi; \
			echo "===> framework $$_fn build FAILED -- see $$_fn/${BUILD_ROOT}/runs/${RUN_ID}/build.log" >&2; \
			if [ "${FAIL_FAST}" = "yes" ]; then exit 1; fi; \
		fi; \
	fi; \
	rm -rf "$$_ws/$$_fn/${BUILD_ROOT}/runs/latest"; \
	cp -a "$$_rundir" "$$_ws/$$_fn/${BUILD_ROOT}/runs/latest"
.endfor

_aggregate_ws:
	@mkdir -p ${.CURDIR:Q}/${BINDIR_LOCAL} ${.CURDIR:Q}/${LIBDIR_LOCAL} \
	          ${.CURDIR:Q}/${SHAREDIR_LOCAL}

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
			${ABI:DABI=${ABI}} BMK_MKDIR=${BMK_MKDIR:Q} || true; \
	done
.if ${CLEAN_ALL_TARGETS} == "yes"
	rm -rf ${.CURDIR:Q}/build ${.CURDIR:Q}/distrib ${.CURDIR:Q}/${BUILD_REPORT_DIR:Q} ${.CURDIR:Q}/${TEST_REPORT_DIR:Q}
	@# full source-only slate: any leftover build/ or generated order files
	@find ${.CURDIR:Q} \( -type d -name build -o -type d -name distrib \) -prune -exec rm -rf {} + 2>/dev/null || true
.else
	rm -rf ${.CURDIR:Q}/${BUILD_ROOT} ${.CURDIR:Q}/${DISTRIB_ROOT}
	@# dashboards are keyed by <RUN_ID-or-latest>/<KEY>/ -- remove just
	@# this target key's data across every run (run-history-not-
	@# overwritten-req), leaving other target keys' history alone, then
	@# prune any run/latest dirs left empty by that removal.
	@for _d in ${.CURDIR:Q}/${BUILD_REPORT_DIR:Q} ${.CURDIR:Q}/${TEST_REPORT_DIR:Q}; do \
		[ -d "$$_d" ] || continue; \
		find "$$_d" -mindepth 2 -maxdepth 2 -type d -name '${OS_ARCH}' -exec rm -rf {} + 2>/dev/null; \
		find "$$_d" -mindepth 1 -maxdepth 1 -type d -empty -delete 2>/dev/null; \
	done
.endif
	rm -f ${.CURDIR:Q}/.gen-fw-order.mk ${.CURDIR:Q}/.gen-mod-order.mk ${.CURDIR:Q}/.depend
	@find ${.CURDIR:Q} -name '.gen-*.mk' -delete 2>/dev/null || true
	@find ${.CURDIR:Q} -name '.depend' -delete 2>/dev/null || true
# @impl 7854-6ad2-03bb-077e (clean-leaves-no-empty-build-dirs-req)
	@rmdir ${.CURDIR:Q}/build ${.CURDIR:Q}/distrib 2>/dev/null || true

# Convenience targets (REQ-add-prereq-add-parent-convenience-targets-req)
# @impl 0f87-6a98-7918-e195
add-parent:
.if !defined(WS) || empty(WS)
	@echo "usage: make add-parent WS=/absolute/path" >&2; exit 1
.endif
	@. ${BMK_MKDIR:Q}/../scripts/bmk-names.sh; _w=$$(bmk_wl ${WS:Q}); \
	_r=$$(printf '%s' "$$_w" | sed -e 's/[\\&|]/\\&/g'); \
	if grep -q '^PARENT_WS' makefile; then \
		sed -i.bak -e "s|^PARENT_WS=\\(.*\\)|PARENT_WS=\\1 $$_r|" makefile; \
	else \
		printf 'PARENT_WS=%s\n' "$$_w" >> makefile; \
	fi
	@echo "Appended ${WS} to PARENT_WS"

# @impl 0f87-6a98-7755-574e
install:
	@echo "install: use DESTDIR= and PREFIX= (PREFIX is project-level)"
	@# Requires pre-built target
	@if [ ! -d ${BUILD_ROOT} ]; then \
		echo "error: ${BUILD_ROOT} does not exist — build first" >&2; exit 1; \
	fi
	@DEST=${DESTDIR:Q}${PREFIX:U/usr/local:Q}; \
	mkdir -p "$$DEST/bin" "$$DEST/lib" "$$DEST/share"; \
	cp -a ${BINDIR_LOCAL}/. "$$DEST/bin/" 2>/dev/null || true; \
	cp -a ${LIBDIR_LOCAL}/. "$$DEST/lib/" 2>/dev/null || true; \
	cp -a ${SHAREDIR_LOCAL}/. "$$DEST/share/" 2>/dev/null || true; \
	echo "===> installed to $$DEST"

# run: convenience target — defined in mk.common.mk (shared across all
# roles) so it also works from a framework/module directory, not just here.

# docs: generate every framework's own docs (PREREQS order, so a
# dependent's tag-file cross-links resolve), then a landing page linking
# each framework's own docs/html/index.html. The landing page gets the
# same project-metadata treatment as each framework's own Doxygen page
# (name/version/brief/logo/license), read from the workspace root -- the
# canonical source frameworks inherit from when they don't override it.
# bmake-docs-scoping-fix-req: the generated landing page lives under
# WS_DOCS_DIR (default build/docs/, matching this project's own
# generated-output convention), NOT the bare, easily-already-taken
# "docs/" a project's own hand-written documentation commonly already
# uses (found in real use: the landing page silently overwrote content
# inside the project's own docs/). DOCS_DIR itself is unchanged and
# still names where EACH FRAMEWORK's own per-framework docs live
# (mk.docs.mk's identical default) -- the landing page's own links to
# them are computed relative to WS_DOCS_DIR's own depth, not hardcoded
# to one directory level up.
# @impl 0f87-6aa9-0267-bd7c
# @impl 0f87-6abe-3f73-763e
DOCS_DIR ?= docs
WS_DOCS_DIR ?= build/docs
_WS_DOCS_UP != printf '%s' "${WS_DOCS_DIR}" | awk -F/ '{s=""; for(i=0;i<NF;i++) s=s"../"; printf "%s", s}'
DOC_PROJECT_NAME ?= ${_CURNAME}
DOC_PROJECT_BRIEF ?=

.if !defined(DOC_PROJECT_VERSION)
.  if exists(${.CURDIR}/VERSION)
DOC_PROJECT_VERSION != cat ${.CURDIR:Q}/VERSION 2>/dev/null | head -1
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
DOC_LICENSE_NOTICE != head -1 ${.CURDIR:Q}/LICENSE 2>/dev/null
.  else
DOC_LICENSE_NOTICE =
.  endif
.endif

docs:
.for _f in ${SUBDIR_FRAMEWORKS}
	@${MAKE} -C ${_f:${_BMK_DEC}:Q} docs BMK_MKDIR=${BMK_MKDIR:Q}
.endfor
	@mkdir -p ${.CURDIR:Q}/${WS_DOCS_DIR:Q}
	@echo "<!DOCTYPE html><html><head><title>${DOC_PROJECT_NAME}</title></head><body>" > ${.CURDIR:Q}/${WS_DOCS_DIR:Q}/index.html
.if !empty(DOC_LOGO)
	@echo "<img src=\"${DOC_LOGO:T}\" alt=\"logo\" height=\"64\">" >> ${.CURDIR:Q}/${WS_DOCS_DIR:Q}/index.html
	@if [ "${DOC_LOGO}" != "${.CURDIR}/${WS_DOCS_DIR}/${DOC_LOGO:T}" ]; then \
		cp ${DOC_LOGO:Q} ${.CURDIR:Q}/${WS_DOCS_DIR:Q}/${DOC_LOGO:T:Q}; \
	fi
.endif
	@echo "<h1>${DOC_PROJECT_NAME}" >> ${.CURDIR:Q}/${WS_DOCS_DIR:Q}/index.html
.if !empty(DOC_PROJECT_VERSION)
	@echo " <small>${DOC_PROJECT_VERSION}</small>" >> ${.CURDIR:Q}/${WS_DOCS_DIR:Q}/index.html
.endif
	@echo "</h1>" >> ${.CURDIR:Q}/${WS_DOCS_DIR:Q}/index.html
.if !empty(DOC_PROJECT_BRIEF)
	@echo "<p>${DOC_PROJECT_BRIEF}</p>" >> ${.CURDIR:Q}/${WS_DOCS_DIR:Q}/index.html
.endif
	@echo "<ul>" >> ${.CURDIR:Q}/${WS_DOCS_DIR:Q}/index.html
.for _f in ${SUBDIR_FRAMEWORKS}
	@if [ -d "${.CURDIR}/${_f:${_BMK_DEC}}/${DOCS_DIR}/html" ]; then \
		echo "<li><a href=\"${_WS_DOCS_UP}${_f:${_BMK_DEC}}/${DOCS_DIR}/html/index.html\">${_f:${_BMK_DEC}}</a></li>" >> ${.CURDIR:Q}/${WS_DOCS_DIR:Q}/index.html; \
	fi
.endfor
	@echo "</ul>" >> ${.CURDIR:Q}/${WS_DOCS_DIR:Q}/index.html
.if !empty(DOC_LICENSE_NOTICE)
	@echo "<p><small>${DOC_LICENSE_NOTICE}</small></p>" >> ${.CURDIR:Q}/${WS_DOCS_DIR:Q}/index.html
.endif
	@echo "</body></html>" >> ${.CURDIR:Q}/${WS_DOCS_DIR:Q}/index.html
	@echo "===> workspace docs complete -> ${WS_DOCS_DIR}/index.html"

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
# test-builds-prerequisite-closure-req: `test` is `all` followed by the
# tests. The workspace test used to enter only frameworks it could run tests
# in, so a prerequisite framework without tests (imported headers and
# libraries only) was never built from a clean tree. A build failure stops
# the run: tests of a tree that does not build would only fail again, later
# and noisier. The frameworks below are told (BMK_TEST_BUILT=yes) not to
# build again.
# cross-test-needs-runner-req: a foreign target with no runner stops here, before
# the build, naming the variables to set. @impl 0f87-6adc-9b69-7c32
.include "${BMK_MKDIR}/mk.crosstest.mk"
# @impl 0f87-6ac1-0a1e-c402
test: _xtest_check _ws_test_build
_ws_test_build:
	@${MAKE} all REPORT=no BMK_REQUIRES_FOR=test \
		TARGET=${TARGET} TARGET_ARCH=${TARGET_ARCH} TOOLCHAIN=${TOOLCHAIN} \
		BMK_MKDIR=${BMK_MKDIR:Q} PARENT_WS="${PARENT_WS}" SANITIZE="${SANITIZE}" FAIL_FAST="${FAIL_FAST}" RUN_ID="${RUN_ID}" \
		|| { echo "===> tests not run: the build failed" >&2; exit 1; }

# @impl 0f87-6ad7-1f32-4d7a (status captured with `|| _trc=$$?`, see _run_tests in mk.framework.mk)
test:
.for _f in ${SUBDIR_FRAMEWORKS}
	@if [ -z "${FW}" ] || [ "${_f:${_BMK_DEC}}" = "${FW}" ]; then \
		_rundir=${.CURDIR:Q}/${_f:${_BMK_DEC}:Q}/${BUILD_ROOT}/runs/${RUN_ID}; mkdir -p "$$_rundir"; \
		_trc=0; \
		${MAKE} -C ${_f:${_BMK_DEC}:Q} test \
			TARGET=${TARGET} TARGET_ARCH=${TARGET_ARCH} TOOLCHAIN=${TOOLCHAIN} \
			BMK_MKDIR=${BMK_MKDIR:Q} PARENT_WS="${PARENT_WS}" SANITIZE="${SANITIZE}" FAIL_FAST="${FAIL_FAST}" \
			REPORT="${REPORT}" TEST="${TEST}" RUN_ID="${RUN_ID}" BMK_TEST_BUILT=yes || _trc=$$?; \
		if [ "$$_trc" -ne 0 ]; then \
			touch "$$_rundir/test.failed"; \
			if [ "${FAIL_FAST}" = "yes" ]; then exit $$_trc; fi; \
		else \
			rm -f "$$_rundir/test.failed"; \
		fi; \
	fi
.endfor
.if ${REPORT} == "yes"
	@mkdir -p ${.CURDIR:Q}/${TEST_REPORT_DIR:Q}/${RUN_ID}/${OS_ARCH}
	@echo "<!DOCTYPE html><html><head><title>${_CURNAME} test dashboard</title>" > ${.CURDIR:Q}/${TEST_REPORT_DIR:Q}/${RUN_ID}/${OS_ARCH}/index.html
	@echo "<style>body{font-family:sans-serif}table{border-collapse:collapse}td,th{border:1px solid #ccc;padding:6px 10px;text-align:left}.fail{color:#b00;font-weight:bold}.pass{color:#080}</style></head><body>" >> ${.CURDIR:Q}/${TEST_REPORT_DIR:Q}/${RUN_ID}/${OS_ARCH}/index.html
	@echo "<h1>${_CURNAME} test dashboard <small>${RUN_ID} / ${OS_ARCH}</small></h1>" >> ${.CURDIR:Q}/${TEST_REPORT_DIR:Q}/${RUN_ID}/${OS_ARCH}/index.html
	@echo "<table><tr><th>Framework</th><th>Module</th><th>Result</th><th>Reports</th></tr>" >> ${.CURDIR:Q}/${TEST_REPORT_DIR:Q}/${RUN_ID}/${OS_ARCH}/index.html
	@. ${BMK_MKDIR:Q}/../scripts/bmk-names.sh; \
	_total_fail=0; _total_pass=0; \
	for _fw in ${SUBDIR_FRAMEWORKS}; do \
		_f=$$(bmk_dec "$$_fw"); \
		[ -z "${FW}" ] || [ "$$_f" = "${FW}" ] || continue; \
		for _mw in $$(${MAKE} -C "$$_f" -V SUBDIR_MODULES 2>/dev/null); do \
			_m=$$(bmk_dec "$$_mw"); \
			if [ -n "${TEST}" ]; then \
				_has=$$(${MAKE} -C "$$_f/$$_m" -V '$${TESTS_CXX} $${TESTS_C} $${TESTS_SH}' 2>/dev/null); \
				case " $$_has " in *" ${TEST} "*) ;; *) continue ;; esac; \
			fi; \
			_html="$$_f/$$_m/${BUILD_ROOT}/runs/${RUN_ID}/test-report-html/index.html"; \
			_xml="$$_f/$$_m/${BUILD_ROOT}/runs/${RUN_ID}/test-results.xml"; \
			[ -f "$$_html" ] || continue; \
			_fails=$$(grep -cE '<(failure|error)' "$$_xml" 2>/dev/null); \
			_fails=$${_fails:-0}; \
			if [ "$$_fails" -gt 0 ]; then \
				_status="<span class=\"fail\">FAIL ($$_fails)</span>"; _total_fail=$$((_total_fail+1)); \
			else \
				_status="<span class=\"pass\">PASS</span>"; _total_pass=$$((_total_pass+1)); \
			fi; \
			echo "<tr><td>$$_f</td><td>$$_m</td><td>$$_status</td><td><a href=\"../../../$$_html\">HTML</a> / <a href=\"../../../$$_xml\">JUnit XML</a></td></tr>" \
				>> ${.CURDIR:Q}/${TEST_REPORT_DIR:Q}/${RUN_ID}/${OS_ARCH}/index.html; \
		done; \
	done; \
	echo "</table><p>$$_total_pass module(s) clean, $$_total_fail module(s) with failures.</p>" \
		>> ${.CURDIR:Q}/${TEST_REPORT_DIR:Q}/${RUN_ID}/${OS_ARCH}/index.html
	@echo "</body></html>" >> ${.CURDIR:Q}/${TEST_REPORT_DIR:Q}/${RUN_ID}/${OS_ARCH}/index.html
	@rm -rf ${.CURDIR:Q}/${TEST_REPORT_DIR:Q}/latest/${OS_ARCH}; mkdir -p ${.CURDIR:Q}/${TEST_REPORT_DIR:Q}/latest
	@cp -a ${.CURDIR:Q}/${TEST_REPORT_DIR:Q}/${RUN_ID}/${OS_ARCH} ${.CURDIR:Q}/${TEST_REPORT_DIR:Q}/latest/${OS_ARCH}
	@echo "===> workspace test dashboard -> ${TEST_REPORT_DIR}/${RUN_ID}/${OS_ARCH}/index.html (also ${TEST_REPORT_DIR}/latest/${OS_ARCH}/)"
.endif
	@# aggregation-failure-exit-code-req: runs last, after the REPORT=yes
	@# dashboard above (if any) so it's generated regardless.
	@# @impl 0f87-6ab5-81a2-7bb0
	@. ${BMK_MKDIR:Q}/../scripts/bmk-names.sh; \
	_failed=""; \
	for _fw in ${SUBDIR_FRAMEWORKS}; do \
		_f=$$(bmk_dec "$$_fw"); \
		[ -z "${FW}" ] || [ "$$_f" = "${FW}" ] || continue; \
		if [ -f ${.CURDIR:Q}/"$$_f/${BUILD_ROOT}/runs/${RUN_ID}/test.failed" ]; then \
			_failed="$$_failed $$_fw"; \
		fi; \
	done; \
	if [ -n "$$_failed" ]; then \
		echo "===> workspace TEST FAILED:$$(for _fw in $$_failed; do printf ' %s' "$$(bmk_dec "$$_fw")"; done)" >&2; \
		for _fw in $$_failed; do \
			_f=$$(bmk_dec "$$_fw"); \
			echo "     $$_f -- see $$_f/${BUILD_ROOT}/runs/${RUN_ID}/test-results.xml" >&2; \
		done; \
		exit 1; \
	fi

.PHONY: all clean help _build_frameworks _aggregate_ws add-parent install docs test _ws_test_build

_LOCAL_MK_PHASE = local
.include "${BMK_MKDIR}/mk.local.mk"

BMK_HELP_ROLE = workspace
.include "${BMK_MKDIR}/mk.help.mk"

.endif # _MK_WORKSPACE_MK_
