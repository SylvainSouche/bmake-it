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
# default it here. gen-mod-order.sh's own _bmake_q already searches
# /opt/local/share/mk, /usr/share/mk, /usr/local/share/mk and picks whichever
# actually exists; hardcoding /opt/local/share/mk here used to short-circuit
# that search on every non-macOS host (BMK_SYS_MK is otherwise never set by
# anything upstream), silently pointing nested -V LIBS/LIB queries at a
# sys.mk that doesn't exist there. Those queries then failed silently (the
# script swallows query errors via `|| true`), so every module looked
# dependency-free and modules were emitted in plain glob order instead of
# topological order -- found empirically: a Linux container built a PROG
# before the LIB it links against, because "app" sorts before "libg".
# @impl 0f87-6a98-5e9c-0a14
_order_generated != cd ${.CURDIR} && 	BMK_MKDIR='${BMK_MKDIR}' 	MAKESYSPATH='${BMK_MKDIR}:/usr/share/mk:/opt/local/share/mk' 	BMK_SYS_MK='${BMK_SYS_MK:U}' 	BMAKE='${MAKE}' 	sh ${_GEN_SCRIPT} ${_ORDER_MK} 2>&1 || echo "FAILED:$$?"
.endif

.-include "${_ORDER_MK}"
.if defined(MODULE_SUBDIR) && !empty(MODULE_SUBDIR)
SUBDIR_MODULES := ${MODULE_SUBDIR}
.else
# Do NOT fall back to alphabetical ls — that builds dependents before deps
.  if exists(${_GEN_SCRIPT})
.    warning "gen-mod-order produced no MODULE_SUBDIR (BMK_MKDIR='${BMK_MKDIR}'); check scripts/gen-mod-order.sh. Falling back to unsorted *.m"
.  endif
SUBDIR_MODULES != ls -d *.m 2>/dev/null || true
.endif

# Surface order in verbose builds
.if make(all) || make(_build_modules)
.  info framework modules (build order): ${SUBDIR_MODULES}
.endif

# ---------------------------------------------------------------------------
# Build all modules in dependency order, then copy-up. Each module's build
# output is always captured to <module>/<BUILD_ROOT>/build.log (tee'd, so
# console output is unchanged). One module's build failure does NOT stop
# every other module from still being attempted -- FAIL_FAST=yes opts
# into stop-on-first-failure instead (build-workspace-aggregation-req,
# report-flag-uniform-trigger).
# ---------------------------------------------------------------------------
all: _build_modules _aggregate
	@echo "===> framework ${.CURDIR:T} complete for ${OS_ARCH}"

# @impl 0f87-6a98-5e47-0c71
# @impl 0f87-6aaa-6a6e-00d0
_build_modules:
.for _m in ${SUBDIR_MODULES}
	@echo "===> building module ${_m}"
	@_logdir=${.CURDIR}/${_m}/${BUILD_ROOT}; mkdir -p "$$_logdir"; \
	_rcfile=$$(mktemp); \
	{ ${MAKE} -C ${_m} all \
		TARGET=${TARGET} TARGET_ARCH=${TARGET_ARCH} TOOLCHAIN=${TOOLCHAIN} \
		BMK_MKDIR=${BMK_MKDIR} PARENT_WS="${PARENT_WS}" SANITIZE="${SANITIZE}" FAIL_FAST="${FAIL_FAST}"; \
	  echo $$? > "$$_rcfile"; } 2>&1 | tee "$$_logdir/build.log"; \
	_rc=$$(cat "$$_rcfile"); rm -f "$$_rcfile"; \
	if [ "$$_rc" -eq 0 ]; then \
		rm -f "$$_logdir/build.failed"; \
		${MAKE} -C ${_m} copy-up \
			TARGET=${TARGET} TARGET_ARCH=${TARGET_ARCH} TOOLCHAIN=${TOOLCHAIN} \
			BMK_MKDIR=${BMK_MKDIR} PARENT_WS="${PARENT_WS}" SANITIZE="${SANITIZE}" FAIL_FAST="${FAIL_FAST}" \
			2>&1 | tee -a "$$_logdir/build.log"; \
	else \
		touch "$$_logdir/build.failed"; \
		echo "===> module ${_m} build FAILED -- see ${_m}/${BUILD_ROOT}/build.log" >&2; \
		if [ "${FAIL_FAST}" = "yes" ]; then exit 1; fi; \
	fi
.endfor

# test: recurse into every module (test-workspace-aggregation-req). A
# module with no TESTS_CXX=/TESTS_C=/TESTS_SH= just echoes and exits 0
# (mk.test.mk's own no-tests branch). One module's genuine test failure
# does NOT stop the loop before every other module has had a chance to
# run, unless FAIL_FAST=yes was given. REPORT=/SANITIZE= are forwarded
# as-is; TEST=<name> is pre-filtered here -- only modules that actually
# declare a matching test get invoked at all, so mk.test.mk's own
# TEST=-with-no-match case only ever fires for a genuine direct mistake,
# not for every module TEST= wasn't meant for.
# @impl 0f87-6aaa-6201-a430
# @impl 0f87-6aaa-697c-4c30
test:
.for _m in ${SUBDIR_MODULES}
	@if [ -n "${TEST}" ]; then \
		_has=$$(${MAKE} -C ${_m} -V '$${TESTS_CXX} $${TESTS_C} $${TESTS_SH}' 2>/dev/null); \
		case " $$_has " in \
			*" ${TEST} "*) _run=yes ;; \
			*) _run=no ;; \
		esac; \
	else \
		_run=yes; \
	fi; \
	if [ "$$_run" = yes ]; then \
		${MAKE} -C ${_m} test \
			TARGET=${TARGET} TARGET_ARCH=${TARGET_ARCH} TOOLCHAIN=${TOOLCHAIN} \
			BMK_MKDIR=${BMK_MKDIR} PARENT_WS="${PARENT_WS}" SANITIZE="${SANITIZE}" FAIL_FAST="${FAIL_FAST}" \
			REPORT="${REPORT}" TEST="${TEST}"; \
		_trc=$$?; \
		if [ "$$_trc" -ne 0 ] && [ "${FAIL_FAST}" = "yes" ]; then exit $$_trc; fi; \
	fi
.endfor

# Aggregate resources (share/ overlay) and ensure dirs exist
_aggregate:
	@mkdir -p ${.CURDIR}/${BINDIR_LOCAL} ${.CURDIR}/${LIBDIR_LOCAL} \
	          ${.CURDIR}/${SHAREDIR_LOCAL} ${.CURDIR}/${INCDIR_LOCAL}
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
copy-up: all
	@_WS=${.CURDIR}/..; \
	sh ${BMK_MKDIR}/../scripts/diff-aware-copy.sh ${.CURDIR}/${BINDIR_LOCAL} $$_WS/${BINDIR_LOCAL}; \
	sh ${BMK_MKDIR}/../scripts/diff-aware-copy.sh ${.CURDIR}/${LIBDIR_LOCAL} $$_WS/${LIBDIR_LOCAL}; \
	sh ${BMK_MKDIR}/../scripts/diff-aware-copy.sh ${.CURDIR}/${SHAREDIR_LOCAL} $$_WS/${SHAREDIR_LOCAL}; \
	echo "===> framework ${.CURDIR:T} copy-up → workspace"

clean:
	@# modules: clean each *.m without relying on order generation
	@for _m in *.m; do \
		[ -d "$$_m" ] || continue; \
		${MAKE} -C "$$_m" clean \
			TARGET=${TARGET} TARGET_ARCH=${TARGET_ARCH} TOOLCHAIN=${TOOLCHAIN} \
			BMK_MKDIR=${BMK_MKDIR} || true; \
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

.PHONY: all clean help copy-up add-prereq _build_modules _aggregate test

.include "${BMK_MKDIR}/mk.docs.mk"

_LOCAL_MK_PHASE = local
.include "${BMK_MKDIR}/mk.local.mk"

BMK_HELP_ROLE = framework
.include "${BMK_MKDIR}/mk.help.mk"

.endif # _MK_FRAMEWORK_MK_
