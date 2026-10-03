# mk.skipped.mk -- the targets of a module or framework that
# PLATFORMS=/TOOLCHAINS= excludes here (platform-toolchain-constraints-dec).
# Included by the role files in place of their normal body, with
# _SK_ROLE = module | framework. Nothing is built, copied up, tested or
# imported; the module's own makefile is not otherwise consulted, so an
# IMPORT= or REQUIRES= that only makes sense elsewhere never runs.
# A skip is intent, not a failure: one informational line, exit 0.
#
# Markers, so a dependent can tell "excluded here" from "failed":
#   a lib module   build/<KEY>/.skipped/<LIB>      (read by the link check)
#   a framework    build/<KEY>/runs/<RUN_ID>/build.excluded  (read by the
#                  workspace loop)
# @impl 0f87-6ac0-d891-3000
# @impl 0f87-6ac0-d892-32c8

_FWDIR = ${.CURDIR}/..
_SK_NAME = ${.CURDIR:T}
_SK_ISLIB = ${_SK_NAME:Mlib*}
.if ${_SK_ROLE} == "module"
.  if defined(LIB) && !empty(LIB)
_SK_LIB = ${LIB}
.  else
_SK_LIB = ${_SK_NAME:S/.m$//:S/^lib//}
.  endif
.endif

.MAIN: all

all:
.if ${_SK_ROLE} == "module"
	@echo "===> module ${.CURDIR:T} skipped: ${_BMK_SKIP_MSG}"
.  if (defined(LIB) && !empty(LIB)) || !empty(_SK_ISLIB)
	@mkdir -p ${_FWDIR}/${BUILD_ROOT}/.skipped; \
	echo "${.CURDIR:T}: ${_BMK_SKIP_MSG}" > ${_FWDIR}/${BUILD_ROOT}/.skipped/${_SK_LIB}
.  endif
.else
	@echo "===> framework ${.CURDIR:T} skipped: ${_BMK_SKIP_MSG}"
	@mkdir -p ${.CURDIR}/${BUILD_ROOT}/runs/${RUN_ID}; \
	echo "${_BMK_SKIP_MSG}" > ${.CURDIR}/${BUILD_ROOT}/runs/${RUN_ID}/build.excluded
.endif

copy-up test docs add-prereq:
	@:

clean:
.if ${CLEAN_ALL_TARGETS} == "yes"
	rm -rf ${.CURDIR}/build
.else
	rm -rf ${.CURDIR}/${BUILD_ROOT}
.endif

.PHONY: all copy-up test docs add-prereq clean
