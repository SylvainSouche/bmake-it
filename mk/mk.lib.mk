# mk.lib.mk — library module role
.if !defined(_MK_LIB_MK_)
_MK_LIB_MK_ = 1

.if !defined(BMK_MKDIR)
.  if exists(${.PARSEDIR}/mk.common.mk)
BMK_MKDIR := ${.PARSEDIR}
.  else
BMK_MKDIR = ${.CURDIR}
.  endif
.endif

.include "${BMK_MKDIR}/mk.common.mk"

# @impl 0f87-6a98-5ff4-1b42
.if !defined(LIB) || empty(LIB)
_libdir != basename ${.CURDIR} .m
# Strip leading lib from directory name (libgreet.m → greet) for conventional -lgreet
LIB != echo ${_libdir} | sed 's/^lib//'
.endif

# @impl 0f87-6a9a-b8d2-c192
# <LIB>_BUILDING (uppercased), for the bmk_export.h BMK_DLLEXPORT/
# BMK_DLLIMPORT pattern (REQ-msvc-shared-lib-export-req): only ever
# defined while compiling THIS module's own sources, never for a
# consumer including the same public header elsewhere, so the header's
# own #if resolves to export here and import there.
CFLAGS   += -D${LIB:tu}_BUILDING
CXXFLAGS += -D${LIB:tu}_BUILDING

# @impl 0f87-6a98-77f0-ca62
.if !defined(LIB_SHARED)
LIB_SHARED = YES
.endif

.if ${LIB_SHARED} == "YES" && (!defined(SHLIB_MAJOR) || empty(SHLIB_MAJOR))
SHLIB_MAJOR = 1
.endif

.if !defined(SRCS) || empty(SRCS)
SRCS != find src -type f \( -name '*.c' -o -name '*.cc' -o -name '*.cpp' -o -name '*.cxx' -o -name '*.y' -o -name '*.l' \) 2>/dev/null | sed 's|^src/||' || true
.endif

.if exists(${.CURDIR}/include)
CFLAGS   += -I${.CURDIR}/include
CXXFLAGS += -I${.CURDIR}/include
.endif

_FWDIR = ${.CURDIR}/..
.if exists(${_FWDIR}/local/include)
CFLAGS   += -I${_FWDIR}/local/include
CXXFLAGS += -I${_FWDIR}/local/include
.endif
.if exists(${_FWDIR}/include)
CFLAGS   += -I${_FWDIR}/include
CXXFLAGS += -I${_FWDIR}/include
.endif
.if exists(${_FWDIR}/${BUILD_ROOT}/include)
CFLAGS   += -I${_FWDIR}/${BUILD_ROOT}/include
CXXFLAGS += -I${_FWDIR}/${BUILD_ROOT}/include
.endif

.if exists(${_FWDIR}/makefile)
_PREREQS != bmake -f ${_FWDIR}/makefile -V PREREQS 2>/dev/null || true
.  for _p in ${_PREREQS}
# REQ-headers-resolved-from-source-req: a PREREQS framework is resolved
# first within the current workspace, then falling back through PARENT_WS
# workspaces in declared order if not found locally.
# @impl 0f87-6a98-5e47-0c71
.    if exists(${_FWDIR}/../${_p})
_PREREQ_BASE.${_p} = ${_FWDIR}/..
.    else
.      for _pws in ${PARENT_WS}
.        if !defined(_PREREQ_BASE.${_p}) && exists(${_pws}/${_p})
_PREREQ_BASE.${_p} = ${_pws}
.        endif
.      endfor
.    endif
.    if defined(_PREREQ_BASE.${_p})
.      if exists(${_PREREQ_BASE.${_p}}/${_p}/include)
CFLAGS   += -I${_PREREQ_BASE.${_p}}/${_p}/include
CXXFLAGS += -I${_PREREQ_BASE.${_p}}/${_p}/include
.      endif
.      if exists(${_PREREQ_BASE.${_p}}/${_p}/${BUILD_ROOT}/include)
CFLAGS   += -I${_PREREQ_BASE.${_p}}/${_p}/${BUILD_ROOT}/include
CXXFLAGS += -I${_PREREQ_BASE.${_p}}/${_p}/${BUILD_ROOT}/include
.      endif
.      if exists(${_PREREQ_BASE.${_p}}/${_p}/${BUILD_ROOT}/lib)
LDFLAGS  += -L${_PREREQ_BASE.${_p}}/${_p}/${BUILD_ROOT}/lib
.      endif
.    endif
.  endfor
.endif

# Always add framework lib path (created by earlier modules during ordered build)
LDFLAGS += -L${_FWDIR}/${BUILD_ROOT}/lib
_LIB_SEARCH_DIRS = ${_FWDIR}/${BUILD_ROOT}/lib
.for _p in ${_PREREQS}
.  if defined(_PREREQ_BASE.${_p}) && exists(${_PREREQ_BASE.${_p}}/${_p}/${BUILD_ROOT}/lib)
_LIB_SEARCH_DIRS += ${_PREREQ_BASE.${_p}}/${_p}/${BUILD_ROOT}/lib
.  endif
.endfor

# @impl 0f87-6a98-76c2-a96e
.for _l in ${LIBS}
LDFLAGS += -l${_l}
.endfor

_OBJDIR = ${.CURDIR}/${OBJDIR}
_LIBOUT_DIR = ${.CURDIR}/${LIBDIR_LOCAL}

# @impl 0f87-6a98-76ed-e260
.if ${TARGET} == "macos"
SHLIB_NAME     = lib${LIB}.${SHLIB_MAJOR}.dylib
SHLIB_LINK     = lib${LIB}.dylib
_SHLIB_LDFLAGS = -dynamiclib -install_name ${SHLIB_NAME} -compatibility_version ${SHLIB_MAJOR} -current_version ${SHLIB_MAJOR}
# @impl 0f87-6a98-96de-331e
.elif ${TARGET} == "win"
# No "lib" prefix and no SONAME-style major-version suffix (neither is a
# Windows convention -- LIB= already strips a leading "lib" project-wide,
# so this falls out naturally); the toolchain-agnostic -shared/--out-implib
# flags below are translated per-toolchain (msvc-cc-wrapper.sh for
# TOOLCHAIN=msvc, understood natively by Cygwin/mingw gcc or clang).
SHLIB_NAME     = ${LIB}.dll
SHLIB_LINK     = ${LIB}.dll
_SHLIB_LDFLAGS = -shared -Wl,--out-implib,${_LIBOUT_DIR}/${LIB}.lib
.else
SHLIB_NAME     = lib${LIB}.so.${SHLIB_MAJOR}
SHLIB_LINK     = lib${LIB}.so
_SHLIB_LDFLAGS = -shared -Wl,-soname,${SHLIB_NAME}
.endif

.if ${TARGET} == "win"
STATIC_NAME = ${LIB}.lib
.else
STATIC_NAME = lib${LIB}.a
.endif

OBJS =
.for _s in ${SRCS}
OBJS += ${_OBJDIR}/${_s:R}.o
.endfor

_create_dirs:
	@mkdir -p ${_OBJDIR} ${_LIBOUT_DIR} ${.CURDIR}/${INCDIR_LOCAL}

.for _s in ${SRCS}
.  if ${_s:E} == "c"
${_OBJDIR}/${_s:R}.o: ${.CURDIR}/src/${_s}
	${CC} ${CFLAGS} -fPIC -c ${.ALLSRC} -o ${.TARGET}
.  elif ${_s:E} == "cc" || ${_s:E} == "cpp" || ${_s:E} == "cxx"
${_OBJDIR}/${_s:R}.o: ${.CURDIR}/src/${_s}
	${CXX} ${CXXFLAGS} -fPIC -c ${.ALLSRC} -o ${.TARGET}
.  elif ${_s:E} == "y"
${_OBJDIR}/${_s:R}.c: ${.CURDIR}/src/${_s}
	${YACC} ${YFLAGS} -d -o ${.TARGET} ${.ALLSRC}
	@if [ -f y.tab.h ]; then mv y.tab.h ${_OBJDIR}/${_s:R}.h; fi
	@mkdir -p ${.CURDIR}/${INCDIR_LOCAL}
	@if [ -f ${_OBJDIR}/${_s:R}.h ]; then cp -f ${_OBJDIR}/${_s:R}.h ${.CURDIR}/${INCDIR_LOCAL}/; fi
${_OBJDIR}/${_s:R}.o: ${_OBJDIR}/${_s:R}.c
	${CC} ${CFLAGS} -fPIC -c ${.ALLSRC} -o ${.TARGET}
.  elif ${_s:E} == "l"
${_OBJDIR}/${_s:R}.c: ${.CURDIR}/src/${_s}
	${LEX} ${LFLAGS} -o ${.TARGET} ${.ALLSRC}
${_OBJDIR}/${_s:R}.o: ${_OBJDIR}/${_s:R}.c
	${CC} ${CFLAGS} -fPIC -c ${.ALLSRC} -o ${.TARGET}
.  endif
.endfor

.if ${LIB_SHARED} == "YES"
all: _create_dirs ${_LIBOUT_DIR}/${SHLIB_NAME} _promote_incl
	@echo "===> built shared ${SHLIB_NAME}"
.else
all: _create_dirs ${_LIBOUT_DIR}/${STATIC_NAME} _promote_incl
	@echo "===> built static ${STATIC_NAME}"
.endif

# @impl 0f87-6a98-8b7f-9215
${_LIBOUT_DIR}/${SHLIB_NAME}: ${OBJS}
.for _l in ${LIBS}
	@_found=no; \
	for _d in ${_LIB_SEARCH_DIRS}; do \
		if [ -f "$$_d/lib${_l}.a" ] || [ -f "$$_d/lib${_l}.so" ] || [ -f "$$_d/lib${_l}.dylib" ] || [ -f "$$_d/${_l}.lib" ]; then \
			_found=yes; break; \
		fi; \
	done; \
	if [ "$$_found" = no ]; then \
		echo "error: cannot link lib${LIB}: prerequisite library ${_l} (from LIBS=) has not been built yet -- searched: ${_LIB_SEARCH_DIRS}" >&2; \
		exit 1; \
	fi
.endfor
	${CC} ${_SHLIB_LDFLAGS} -o ${.TARGET} ${OBJS} ${LDFLAGS}
.if ${TARGET} != "win"
	@ln -sfn ${SHLIB_NAME} ${_LIBOUT_DIR}/${SHLIB_LINK} 2>/dev/null || cp -f ${.TARGET} ${_LIBOUT_DIR}/${SHLIB_LINK}
	@${AR} rcs ${_LIBOUT_DIR}/${STATIC_NAME} ${OBJS}
.endif
# win: SHLIB_LINK == SHLIB_NAME (no separate unversioned symlink target on
# Windows), and STATIC_NAME == the import library link.exe's own
# --out-implib already wrote via _SHLIB_LDFLAGS above -- both lines above
# would be redundant-to-harmful (the AR line would silently overwrite the
# import lib with a plain static archive of the same objects) so are
# skipped entirely for win, not just no-ops.

${_LIBOUT_DIR}/${STATIC_NAME}: ${OBJS}
	${AR} rcs ${.TARGET} ${OBJS}

# @impl 0f87-6a98-7718-886d
_promote_incl:
.if defined(INCL) && !empty(INCL)
	@mkdir -p ${_FWDIR}/${BUILD_ROOT}/include
.  for _h in ${INCL}
	@if [ -f ${.CURDIR}/${INCDIR_LOCAL}/${_h} ]; then \
		cp -f ${.CURDIR}/${INCDIR_LOCAL}/${_h} ${_FWDIR}/${BUILD_ROOT}/include/; \
		echo "===> promoted ${_h}"; \
	elif [ -f ${_OBJDIR}/${_h} ]; then \
		cp -f ${_OBJDIR}/${_h} ${_FWDIR}/${BUILD_ROOT}/include/; \
		echo "===> promoted ${_h}"; \
	fi
.  endfor
.endif

# @impl 0f87-6a98-8ee9-ae83
copy-up: all
	@sh ${BMK_MKDIR}/../scripts/diff-aware-copy.sh ${_LIBOUT_DIR} ${_FWDIR}/${LIBDIR_LOCAL}
	@echo "===> copy-up lib${LIB} → framework ${LIBDIR_LOCAL}/"

clean:
.if ${CLEAN_ALL_TARGETS} == "yes"
	rm -rf ${.CURDIR}/build
.else
	rm -rf ${.CURDIR}/${BUILD_ROOT}
.endif
	rm -f *.o *.obj *.core *.dylib *.so *.so.* *.a *.lib *.dll 2>/dev/null || true
	rm -f ${.CURDIR}/.gen-mod-order.mk ${.CURDIR}/.depend 2>/dev/null || true


BMK_HELP_ROLE = lib
.include "${BMK_MKDIR}/mk.help.mk"

.PHONY: all clean help copy-up _create_dirs _promote_incl help
.endif

