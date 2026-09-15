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

.PHONY: all clean help _build_frameworks _aggregate_ws add-parent install docs

_LOCAL_MK_PHASE = local
.include "${BMK_MKDIR}/mk.local.mk"

BMK_HELP_ROLE = workspace
.include "${BMK_MKDIR}/mk.help.mk"

.endif # _MK_WORKSPACE_MK_
