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
# Default target: build all frameworks in PREREQS order, then aggregate
# ---------------------------------------------------------------------------
all: _build_frameworks _aggregate_ws
	@echo "===> workspace build complete for ${OS_ARCH}"

.if !defined(SUBDIR_FRAMEWORKS)
SUBDIR_FRAMEWORKS := ${FRAMEWORK_SUBDIR}
.endif

# @impl 0f87-6a98-5e47-0c71
_build_frameworks:
.for _f in ${SUBDIR_FRAMEWORKS}
	@echo "===> building framework ${_f}"
	@${MAKE} -C ${_f} all \
		TARGET=${TARGET} TARGET_ARCH=${TARGET_ARCH} TOOLCHAIN=${TOOLCHAIN} \
		BMK_MKDIR=${BMK_MKDIR} PARENT_WS="${PARENT_WS}"
	@${MAKE} -C ${_f} copy-up \
		TARGET=${TARGET} TARGET_ARCH=${TARGET_ARCH} TOOLCHAIN=${TOOLCHAIN} \
		BMK_MKDIR=${BMK_MKDIR} PARENT_WS="${PARENT_WS}"
.endfor

_aggregate_ws:
	@mkdir -p ${.CURDIR}/${BINDIR_LOCAL} ${.CURDIR}/${LIBDIR_LOCAL} \
	          ${.CURDIR}/${SHAREDIR_LOCAL}

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
	rm -rf ${.CURDIR}/build ${.CURDIR}/distrib
	@# full source-only slate: any leftover build/ or generated order files
	@find ${.CURDIR} \( -type d -name build -o -type d -name distrib \) -prune -exec rm -rf {} + 2>/dev/null || true
.else
	rm -rf ${.CURDIR}/${BUILD_ROOT} ${.CURDIR}/${DISTRIB_ROOT}
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

.PHONY: all clean help _build_frameworks _aggregate_ws add-parent install


BMK_HELP_ROLE = workspace
.include "${BMK_MKDIR}/mk.help.mk"

.endif # _MK_WORKSPACE_MK_
