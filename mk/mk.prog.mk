# mk.prog.mk — executable module role
.if !defined(_MK_PROG_MK_)
_MK_PROG_MK_ = 1

.if !defined(BMK_MKDIR)
.  if exists(${.PARSEDIR}/mk.common.mk)
BMK_MKDIR := ${.PARSEDIR}
.  else
BMK_MKDIR = ${.CURDIR}
.  endif
.endif

.include "${BMK_MKDIR}/mk.common.mk"

# ---------------------------------------------------------------------------
# Local customization hooks (local-mk-hook-files-and-cascade-order-req)
# Module level sees PARENT_WS's mk/ (outermost), workspace's, framework's,
# then its own -- outer to inner, all included, in that order.
# ---------------------------------------------------------------------------
_LOCAL_MK_DIRS =
.for _p in ${_PARENT_WS_E}
_LOCAL_MK_DIRS += ${_p}/mk
.endfor
_LOCAL_MK_DIRS += ${.CURDIR:${_BMK_ENCW}}/../../mk ${.CURDIR:${_BMK_ENCW}}/../mk ${.CURDIR:${_BMK_ENCW}}/mk

_LOCAL_MK_PHASE = pre
.include "${BMK_MKDIR}/mk.local.mk"
.include "${BMK_MKDIR}/mk.resolved.mk"
.include "${BMK_MKDIR}/mk.constraints.mk"
.if ${_BMK_BUILD} == "yes"
.include "${BMK_MKDIR}/mk.requires.mk"

# @impl 0f87-6a98-5ff4-1b42
.if !defined(PROG) || empty(PROG)
PROG != basename ${.CURDIR:Q} .m
.endif

# Windows requires the .exe extension for PATH lookup / shell execution --
# unlike LIB='s "lib" prefix stripping (default-only), this applies even
# to an explicitly-given PROG=, since it's a hard platform requirement,
# not a naming convention.
# @impl 0f87-6a98-96de-331e
.if ${TARGET} == "win" && empty(PROG:M*.exe)
PROG := ${PROG}.exe
.endif

.if !defined(SRCS) || empty(SRCS)
# hidden-files-not-sources-req: `! -path '*/.*'` skips dot-files and
# dot-directories -- macOS AppleDouble sidecars (._raster.cpp, created by a
# tar extraction elsewhere) are not source and failed to compile.
# @impl 0f87-6ac0-c275-ed0e
SRCS != find src -type f \( -name '*.c' -o -name '*.cc' -o -name '*.cpp' -o -name '*.cxx' -o -name '*.y' -o -name '*.l' \) ! -path '*/.*' 2>/dev/null | sed 's|^src/||' || true
.endif

# Link driver selection (cxx-link-driver-selection-req): ${CXX} when SRCS
# contains a C++ source or LINK_CXX=yes overrides it explicitly (e.g. a
# C-sources-only module linking a static C++ library), ${CC} otherwise.
# @impl 0f87-6ab5-7f76-0dcf
_HAS_CXX_SRCS = no
.for _e in ${_CXX_EXTS}
.  if !empty(SRCS:M*.${_e})
_HAS_CXX_SRCS = yes
.  endif
.endfor
.if (defined(LINK_CXX) && ${LINK_CXX} == "yes") || ${_HAS_CXX_SRCS} == "yes"
_CCLINK = ${CXX}
.else
_CCLINK = ${CC}
.endif

_FWDIR = ${.CURDIR}/..
# where headers and libraries are found: the module's, its framework's, the PREREQS= frameworks'
.include "${BMK_MKDIR}/mk.searchpaths.mk"

_OBJDIR = ${.CURDIR}/${OBJDIR}
# Relative to the module directory -- bmake always runs there -- so that no
# character of the directory's path (an '=' read as an assignment, a '%' read
# as a pattern) ever sits in a target or prerequisite of a rule below
# (path-characters-supported-req). The same holds for _INPUTS_HASH_FILE, and for
# the compiler's -o: the .d file it writes names its target as it was given.
# @impl 0f87-6af0-8ab0-6f2f
_BINOUT = ${BINDIR_LOCAL}/${PROG}

OBJS =
.for _s in ${SRCS}
OBJS += ${OBJDIR}/${_s:R}.o
.endfor

_create_dirs:
	@mkdir -p ${_OBJDIR:Q} ${.CURDIR:Q}/${BINDIR_LOCAL}

# nested-srcs-objdir-req: see mk.lib.mk's identical comment -- each
# compile rule below mkdir -p's its own ${.TARGET:H} first, so a nested
# SRCS= entry works regardless of what else may or may not have already
# created its subdirectory.
# @impl 0f87-6aba-a54a-f741
.for _s in ${SRCS}
.  if ${_s:E} == "c"
${OBJDIR}/${_s:R}.o: src/${_s} ${_INPUTS_HASH_FILE}
	@mkdir -p ${.TARGET:H}
	${CC} ${CFLAGS} ${_DEP_CFLAGS} ${_DEP_CFLAGS:D-MF ${OBJDIR}/${_s:R}.d} -c src/${_s} -o ${.TARGET}
.  elif !empty(_CXX_EXTS:M${_s:E})
${OBJDIR}/${_s:R}.o: src/${_s} ${_INPUTS_HASH_FILE}
	@mkdir -p ${.TARGET:H}
	${CXX} ${CXXFLAGS} ${_DEP_CFLAGS} ${_DEP_CFLAGS:D-MF ${OBJDIR}/${_s:R}.d} -c src/${_s} -o ${.TARGET}
.  elif ${_s:E} == "y"
${OBJDIR}/${_s:R}.c: src/${_s}
	@mkdir -p ${.TARGET:H}
	${YACC} ${YFLAGS} -d -o ${.TARGET} ${.ALLSRC}
	@if [ -f y.tab.h ]; then mv y.tab.h ${OBJDIR}/${_s:R}.h; fi
${OBJDIR}/${_s:R}.o: ${OBJDIR}/${_s:R}.c ${_INPUTS_HASH_FILE}
	@mkdir -p ${.TARGET:H}
	${CC} ${CFLAGS} ${_DEP_CFLAGS} ${_DEP_CFLAGS:D-MF ${OBJDIR}/${_s:R}.d} -c ${OBJDIR}/${_s:R}.c -o ${.TARGET}
.  elif ${_s:E} == "l"
${OBJDIR}/${_s:R}.c: src/${_s}
	@mkdir -p ${.TARGET:H}
	${LEX} ${LFLAGS} -o ${.TARGET} ${.ALLSRC}
${OBJDIR}/${_s:R}.o: ${OBJDIR}/${_s:R}.c ${_INPUTS_HASH_FILE}
	@mkdir -p ${.TARGET:H}
	${CC} ${CFLAGS} ${_DEP_CFLAGS} ${_DEP_CFLAGS:D-MF ${OBJDIR}/${_s:R}.d} -c ${OBJDIR}/${_s:R}.c -o ${.TARGET}
.  endif
# header-dependency-tracking-req: absent on the first build of this
# source (no .o exists yet to have produced it), present and consulted
# on every rebuild after. Plain conditional .include, not bmake's newer
# .dinclude -- its availability on the phase-1 FreeBSD/NetBSD base-make
# targets hasn't been checked from this (macOS-only) host.
.  if exists(${_OBJDIR}/${_s:R}.d)
.    include "${_OBJDIR}/${_s:R}.d"
.  endif
.endfor

all: _check_inputs_hash _create_dirs _create_prereq_links ${_BINOUT}
	@:

# @impl 0f87-6a98-8b7f-9215
# @impl 7854-6ad0-fb85-c2c6 (any of _LIB_FILE_FORMS, lib<n>.dll.a included)
${_BINOUT}: ${OBJS} ${_LIBS_FILES} ${_DELAYLOAD_FILES}
	@${_DELAYLOAD_NAMED}
.for _l in ${_DELAYLOAD_ERRORS}
	@echo "error: cannot delay-load ${_l} into ${PROG}: "${_DELAY_ERR.${_l}:Q} >&2; exit 1
.endfor
.for _l in ${_DELAYLOAD_NOTES}
	@echo "note: DELAYLOAD.${_l}=yes has no effect on ${BMK_TARGET_KEY:U${TARGET}}: delay loading exists only for MSVC and mingw-w64 output, so ${_l} loads when ${PROG} starts"
.endfor
.for _l in ${LIBS}
	@_found=no; \
	for _d in ${_LIB_SEARCH_DIRS_SH}; do \
		for _f in ${_LIB_FILE_FORMS:S/@/${_l}/g}; do \
			if [ -f "$$_d/$$_f" ]; then _found=yes; break 2; fi; \
		done; \
	done; \
	if [ "$$_found" = no ]; then \
		for _d in ${_LIB_SEARCH_DIRS_SH}; do \
			if [ -f "$$_d/../.skipped/${_l}" ]; then \
				echo "error: cannot link ${PROG}: library ${_l} is not built here -- $$(cat "$$_d/../.skipped/${_l}") -- ${_CURNAME} depends on it, so give it the same PLATFORMS=/TOOLCHAINS=" >&2; \
				exit 1; \
			fi; \
		done; \
		echo "error: cannot link ${PROG}: prerequisite library ${_l} (from LIBS=) has not been built yet -- searched: ${_LIB_SEARCH_DIRS:${_BMK_DEC}}" >&2; \
		exit 1; \
	fi
.endfor
# duplicate-linkdeps-fix-req/ldflags-dedup-hook-timing-fix-req:
# transitive .linkdeps expansion (above) can legitimately name the same
# -l<name>/-L<dir>/-Wl,-rpath,<dir> more than once -- two different
# LIBS= entries sharing a common transitive dependency both carry it
# forward. Harmless to the linker itself (ld just warns and ignores the
# repeat), but the warning is pure noise (found in real use: "ignoring
# duplicate libraries" on every link). Computed HERE, inside the
# recipe, not as a top-level != assignment: a top-level != runs at
# parse time, before mk.local.mk's own "local"-phase post-hooks
# contribute to LDFLAGS (below, in this same file) -- a hook-added flag
# silently never reached the link line (a real regression, found in
# use). A recipe only runs after the whole file is parsed, so ${LDFLAGS}
# here already reflects every hook phase. Deduplication is restricted
# to -l*/-L*/-Wl,-rpath,* -- exactly what .linkdeps expansion repeats --
# every other token is passed through unchanged and never compared:
# deduplicating by single word previously split a flag+argument pair
# (`-framework X`, `-Xlinker X`, ...), silently losing the argument or
# the repeated flag. First-occurrence-preserving, not a blind
# sort+uniq -- static link order can matter.
# @impl 0f87-6abe-3f50-0560
# @impl 0f87-6abe-8c3c-9ca3
# recipe-paths-quoted-req: the flags are passed on as an argument list (set --, "$@"), not a
# string split again at its spaces.
# @impl 0f87-6af0-c379-1630
# msvc-cc-shell-quoting-req: the link command is echoed with :Q, never
# inside "..." (MSVC's INCLUDE=\"...;...\" in CC split the line).
# @impl 7854-6adf-d52c-bc05
	@_seen=""; set --; \
	for _f in ${LDFLAGS}; do \
		_skip=no; \
		case "$$_f" in \
			-l*|-L*|-Wl,-rpath,*) \
				case " $$_seen " in \
					*" $$_f "*) _skip=yes ;; \
				esac; \
				[ "$$_skip" = no ] && _seen="$$_seen $$_f" ;; \
		esac; \
		[ "$$_skip" = no ] && set -- "$$@" "$$_f"; \
	done; \
	echo ${_CCLINK:Q} -o ${.TARGET} ${OBJS} "$$@"; \
	${_CCLINK} -o ${.TARGET} ${OBJS} "$$@"
	@echo "===> built ${PROG} → ${BINDIR_LOCAL}/${PROG}"

# @impl 0f87-6a98-8ee9-ae83
copy-up: all
	@sh ${BMK_MKDIR:Q}/../scripts/diff-aware-copy.sh ${.CURDIR:Q}/${BINDIR_LOCAL} ${_FWDIR:Q}/${BINDIR_LOCAL}
	@echo "===> copy-up ${PROG} → framework ${BINDIR_LOCAL}/"

clean:
.if ${CLEAN_ALL_TARGETS} == "yes"
	rm -rf ${.CURDIR:Q}/build
.else
	rm -rf ${.CURDIR:Q}/${BUILD_ROOT}
.endif
	rm -f ${PROG} *.o *.obj *.core *.dylib *.so *.so.* *.a *.lib *.exe 2>/dev/null || true
	rm -f ${.CURDIR:Q}/.gen-mod-order.mk ${.CURDIR:Q}/.depend 2>/dev/null || true
# clean-leaves-no-empty-build-dirs-req: an empty build/ left here kept the
# module directory alive after git switch. rmdir only removes it if empty.
# @impl 7854-6ad2-03bb-077e
	@rmdir ${.CURDIR:Q}/build 2>/dev/null || true


.include "${BMK_MKDIR}/mk.test.mk"

_LOCAL_MK_PHASE = local
.include "${BMK_MKDIR}/mk.local.mk"

BMK_HELP_ROLE = prog
.include "${BMK_MKDIR}/mk.help.mk"

.PHONY: all clean help copy-up _create_dirs _create_prereq_links help
.else
_SK_ROLE = module
.include "${BMK_MKDIR}/mk.skipped.mk"
.endif
.endif

