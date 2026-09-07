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

# @impl 0f87-6a98-5ff4-1b42
.if !defined(PROG) || empty(PROG)
PROG != basename ${.CURDIR} .m
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
_BINOUT = ${.CURDIR}/${BINDIR_LOCAL}/${PROG}

OBJS =
.for _s in ${SRCS}
OBJS += ${_OBJDIR}/${_s:R}.o
.endfor

_create_dirs:
	@mkdir -p ${_OBJDIR} ${.CURDIR}/${BINDIR_LOCAL}

.for _s in ${SRCS}
.  if ${_s:E} == "c"
${_OBJDIR}/${_s:R}.o: ${.CURDIR}/src/${_s}
	${CC} ${CFLAGS} -c ${.ALLSRC} -o ${.TARGET}
.  elif ${_s:E} == "cc" || ${_s:E} == "cpp" || ${_s:E} == "cxx"
${_OBJDIR}/${_s:R}.o: ${.CURDIR}/src/${_s}
	${CXX} ${CXXFLAGS} -c ${.ALLSRC} -o ${.TARGET}
.  elif ${_s:E} == "y"
${_OBJDIR}/${_s:R}.c: ${.CURDIR}/src/${_s}
	${YACC} ${YFLAGS} -d -o ${.TARGET} ${.ALLSRC}
	@if [ -f y.tab.h ]; then mv y.tab.h ${_OBJDIR}/${_s:R}.h; fi
${_OBJDIR}/${_s:R}.o: ${_OBJDIR}/${_s:R}.c
	${CC} ${CFLAGS} -c ${.ALLSRC} -o ${.TARGET}
.  elif ${_s:E} == "l"
${_OBJDIR}/${_s:R}.c: ${.CURDIR}/src/${_s}
	${LEX} ${LFLAGS} -o ${.TARGET} ${.ALLSRC}
${_OBJDIR}/${_s:R}.o: ${_OBJDIR}/${_s:R}.c
	${CC} ${CFLAGS} -c ${.ALLSRC} -o ${.TARGET}
.  endif
.endfor

all: _create_dirs ${_BINOUT}
	@echo "===> built ${PROG} → ${BINDIR_LOCAL}/${PROG}"

# @impl 0f87-6a98-8b7f-9215
${_BINOUT}: ${OBJS}
.for _l in ${LIBS}
	@_found=no; \
	for _d in ${_LIB_SEARCH_DIRS}; do \
		if [ -f "$$_d/lib${_l}.a" ] || [ -f "$$_d/lib${_l}.so" ] || [ -f "$$_d/lib${_l}.dylib" ] || [ -f "$$_d/${_l}.lib" ]; then \
			_found=yes; break; \
		fi; \
	done; \
	if [ "$$_found" = no ]; then \
		echo "error: cannot link ${PROG}: prerequisite library ${_l} (from LIBS=) has not been built yet -- searched: ${_LIB_SEARCH_DIRS}" >&2; \
		exit 1; \
	fi
.endfor
	${CC} -o ${.TARGET} ${OBJS} ${LDFLAGS}

# @impl 0f87-6a98-8ee9-ae83
copy-up: all
	@sh ${BMK_MKDIR}/../scripts/diff-aware-copy.sh ${.CURDIR}/${BINDIR_LOCAL} ${_FWDIR}/${BINDIR_LOCAL}
	@echo "===> copy-up ${PROG} → framework ${BINDIR_LOCAL}/"

clean:
.if ${CLEAN_ALL_TARGETS} == "yes"
	rm -rf ${.CURDIR}/build
.else
	rm -rf ${.CURDIR}/${BUILD_ROOT}
.endif
	rm -f ${PROG} *.o *.obj *.core *.dylib *.so *.so.* *.a *.lib *.exe 2>/dev/null || true
	rm -f ${.CURDIR}/.gen-mod-order.mk ${.CURDIR}/.depend 2>/dev/null || true


BMK_HELP_ROLE = prog
.include "${BMK_MKDIR}/mk.help.mk"

.PHONY: all clean help copy-up _create_dirs help
.endif

