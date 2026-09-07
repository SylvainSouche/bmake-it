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
# Build all modules in dependency order, then copy-up
# ---------------------------------------------------------------------------
all: _build_modules _aggregate
	@echo "===> framework ${.CURDIR:T} complete for ${OS_ARCH}"

# @impl 0f87-6a98-5e47-0c71
_build_modules:
.for _m in ${SUBDIR_MODULES}
	@echo "===> building module ${_m}"
	@${MAKE} -C ${_m} all \
		TARGET=${TARGET} TARGET_ARCH=${TARGET_ARCH} TOOLCHAIN=${TOOLCHAIN} \
		BMK_MKDIR=${BMK_MKDIR} PARENT_WS="${PARENT_WS}"
	@${MAKE} -C ${_m} copy-up \
		TARGET=${TARGET} TARGET_ARCH=${TARGET_ARCH} TOOLCHAIN=${TOOLCHAIN} \
		BMK_MKDIR=${BMK_MKDIR} PARENT_WS="${PARENT_WS}"
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

.PHONY: all clean help copy-up add-prereq _build_modules _aggregate


BMK_HELP_ROLE = framework
.include "${BMK_MKDIR}/mk.help.mk"

.endif # _MK_FRAMEWORK_MK_
