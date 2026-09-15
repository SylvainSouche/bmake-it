# mk.docs.mk — Doxygen-based documentation generation
# Included by mk.framework.mk (per-framework `docs` target) and
# mk.workspace.mk (workspace-level `docs` target, PREREQS-ordered).
#
# Each framework gets its own Doxyfile + HTML output + tag file under
# <framework>/docs/. Cross-framework links resolve via Doxygen's TAGFILES
# mechanism, consuming any PREREQS= framework's tag file that already
# exists -- best-effort, not force-built (framework-scoped `docs` documents
# only that framework; workspace-scoped `docs` iterates in PREREQS order,
# so by the time a dependent framework runs, its prereqs' tag files exist).
#
# Project metadata (name/version/brief/logo/license) uses Doxygen's own
# standard fields -- PROJECT_NAME/PROJECT_NUMBER/PROJECT_BRIEF/PROJECT_LOGO
# and a generated HTML_FOOTER for copyright/license -- rather than a
# custom mechanism. Everything is override-able via DOC_PROJECT_*= macros;
# absent an override, values are auto-detected from conventional files
# (workspace-root VERSION/LICENSE, a docs/logo.* file) and simply omitted
# if not found -- optional throughout, per "corporate info and logos if
# exists".

.if !defined(_MK_DOCS_MK_)
_MK_DOCS_MK_ = 1

DOXYGEN ?= doxygen
DOCS_DIR ?= docs
_DOXYFILE = ${.CURDIR}/${DOCS_DIR}/Doxyfile
_TAGFILE  = ${.CURDIR}/${DOCS_DIR}/${.CURDIR:T}.tag
_DOXFOOTER = ${.CURDIR}/${DOCS_DIR}/footer.html

# TAGFILES entries for each PREREQS= framework whose own tag file already
# exists -- sibling directory, so paths are relative to THIS framework.
_DOXY_TAGFILES =
.for _p in ${PREREQS}
.  if exists(${.CURDIR}/../${_p}/${DOCS_DIR}/${_p}.tag)
_DOXY_TAGFILES += ../${_p}/${DOCS_DIR}/${_p}.tag=../../${_p}/${DOCS_DIR}/html
.  endif
.endfor

# --- Project metadata: override-able, else auto-detected, else omitted ---
DOC_PROJECT_NAME ?= ${.CURDIR:T}
DOC_PROJECT_BRIEF ?=

# Version: workspace-root VERSION file (one level up from a framework).
.if !defined(DOC_PROJECT_VERSION)
.  if exists(${.CURDIR}/../VERSION)
DOC_PROJECT_VERSION != cat ${.CURDIR}/../VERSION 2>/dev/null | head -1
.  else
DOC_PROJECT_VERSION =
.  endif
.endif

# Logo: framework-level docs/logo.{png,svg} first, else workspace-level.
.if !defined(DOC_LOGO)
.  if exists(${.CURDIR}/${DOCS_DIR}/logo.png)
DOC_LOGO = ${.CURDIR}/${DOCS_DIR}/logo.png
.  elif exists(${.CURDIR}/${DOCS_DIR}/logo.svg)
DOC_LOGO = ${.CURDIR}/${DOCS_DIR}/logo.svg
.  elif exists(${.CURDIR}/../${DOCS_DIR}/logo.png)
DOC_LOGO = ${.CURDIR}/../${DOCS_DIR}/logo.png
.  elif exists(${.CURDIR}/../${DOCS_DIR}/logo.svg)
DOC_LOGO = ${.CURDIR}/../${DOCS_DIR}/logo.svg
.  else
DOC_LOGO =
.  endif
.endif

# License/copyright footer: workspace-root LICENSE file, first line only
# (full text belongs in the LICENSE file itself, not duplicated per page).
.if !defined(DOC_LICENSE_NOTICE)
.  if exists(${.CURDIR}/../LICENSE)
DOC_LICENSE_NOTICE != head -1 ${.CURDIR}/../LICENSE 2>/dev/null
.  else
DOC_LICENSE_NOTICE =
.  endif
.endif

# docs: generate this framework's own public-scope HTML docs + tag file.
# @impl 0f87-6aa9-025e-d5c5
docs:
	@mkdir -p ${.CURDIR}/${DOCS_DIR}
	@echo "PROJECT_NAME = ${DOC_PROJECT_NAME}" > ${_DOXYFILE}
.if !empty(DOC_PROJECT_VERSION)
	@echo "PROJECT_NUMBER = ${DOC_PROJECT_VERSION}" >> ${_DOXYFILE}
.endif
.if !empty(DOC_PROJECT_BRIEF)
	@echo "PROJECT_BRIEF = \"${DOC_PROJECT_BRIEF}\"" >> ${_DOXYFILE}
.endif
.if !empty(DOC_LOGO)
	@echo "PROJECT_LOGO = ${DOC_LOGO}" >> ${_DOXYFILE}
.endif
	@echo "OUTPUT_DIRECTORY = ${.CURDIR}/${DOCS_DIR}" >> ${_DOXYFILE}
	@echo "INPUT = ${.CURDIR}/include" >> ${_DOXYFILE}
	@echo "RECURSIVE = YES" >> ${_DOXYFILE}
	@echo "GENERATE_HTML = YES" >> ${_DOXYFILE}
	@echo "GENERATE_LATEX = NO" >> ${_DOXYFILE}
	@echo "GENERATE_TAGFILE = ${_TAGFILE}" >> ${_DOXYFILE}
	@echo "QUIET = YES" >> ${_DOXYFILE}
	@echo "WARN_IF_UNDOCUMENTED = NO" >> ${_DOXYFILE}
.for _t in ${_DOXY_TAGFILES}
	@echo "TAGFILES += ${_t}" >> ${_DOXYFILE}
.endfor
.if !empty(DOC_LICENSE_NOTICE)
	@echo "<p>${DOC_LICENSE_NOTICE}</p>" > ${_DOXFOOTER}
	@echo "</body></html>" >> ${_DOXFOOTER}
	@echo "HTML_FOOTER = ${_DOXFOOTER}" >> ${_DOXYFILE}
.endif
	@${DOXYGEN} ${_DOXYFILE}
	@echo "===> docs generated for ${.CURDIR:T} -> ${DOCS_DIR}/html/index.html"

.PHONY: docs

.endif # _MK_DOCS_MK_
