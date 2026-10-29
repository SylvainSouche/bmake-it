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

# (_check_requires: an excluded framework has nothing to check -- the
# workspace's preflight asks every framework, requires-preflight-req)
copy-up _copy_up test docs add-prereq _fw_build_closure _check_requires:
	@:

clean:
.if ${CLEAN_ALL_TARGETS} == "yes"
	rm -rf ${.CURDIR}/build
.else
	rm -rf ${.CURDIR}/${BUILD_ROOT}
.endif
# @impl 7854-6ad2-03bb-077e (clean-leaves-no-empty-build-dirs-req)
	@rmdir ${.CURDIR}/build 2>/dev/null || true

.PHONY: all copy-up test docs add-prereq _fw_build_closure clean
