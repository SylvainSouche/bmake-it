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
.for _p in ${PARENT_WS}
_LOCAL_MK_DIRS += ${_p}/mk
.endfor
_LOCAL_MK_DIRS += ${.CURDIR}/../../mk ${.CURDIR}/../mk ${.CURDIR}/mk

_LOCAL_MK_PHASE = pre
.include "${BMK_MKDIR}/mk.local.mk"

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
# public-headers-system-req (D3): a framework may opt its whole public
# header surface into -isystem for consumers, typically because it
# wraps/vendors third-party code -- an explicit, framework-level
# declaration, not inferred from any module's own WARN= setting.
.      if exists(${_PREREQ_BASE.${_p}}/${_p}/makefile)
_PREREQ_SYS.${_p} != bmake -f ${_PREREQ_BASE.${_p}}/${_p}/makefile -V PUBLIC_HEADERS_SYSTEM 2>/dev/null || true
.      endif
.      if ${_PREREQ_SYS.${_p}:Uno} == "yes"
_INCFLAG.${_p} = -isystem
.      else
_INCFLAG.${_p} = -I
.      endif
.      if exists(${_PREREQ_BASE.${_p}}/${_p}/include)
CFLAGS   += ${_INCFLAG.${_p}}${_PREREQ_BASE.${_p}}/${_p}/include
CXXFLAGS += ${_INCFLAG.${_p}}${_PREREQ_BASE.${_p}}/${_p}/include
.      endif
.      if exists(${_PREREQ_BASE.${_p}}/${_p}/${BUILD_ROOT}/include)
CFLAGS   += ${_INCFLAG.${_p}}${_PREREQ_BASE.${_p}}/${_p}/${BUILD_ROOT}/include
CXXFLAGS += ${_INCFLAG.${_p}}${_PREREQ_BASE.${_p}}/${_p}/${BUILD_ROOT}/include
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

# Runtime search path for LIBS= -- link-time -L/-l success doesn't imply
# the resulting binary can find the shared lib at run time (see mk.lib.mk
# for the same reasoning). No rpath concept on Windows.
# @impl 0f87-6aa9-448d-537c
.if ${TARGET} != "win"
.  for _d in ${_LIB_SEARCH_DIRS}
LDFLAGS += -Wl,-rpath,${_d}
.  endfor
.endif

# @impl 0f87-6a98-76c2-a96e
# import-link-transitivity-req: see mk.lib.mk's identical comment -- a
# PROG has no lib${LIB}.linkdeps of its own to write (nothing links
# against a PROG), only the consumer-side read.
# @impl 0f87-6ab5-8e46-cfb1
.for _l in ${LIBS}
LDFLAGS += -l${_l}
.  for _d in ${_LIB_SEARCH_DIRS}
.    if exists(${_d}/lib${_l}.linkdeps)
_LINKDEPS.${_l} != cat ${_d}/lib${_l}.linkdeps
LDFLAGS += ${_LINKDEPS.${_l}}
.    endif
.  endfor
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
${_OBJDIR}/${_s:R}.o: ${.CURDIR}/src/${_s} ${_INPUTS_HASH_FILE}
	${CC} ${CFLAGS} ${_DEP_CFLAGS} ${_DEP_CFLAGS:D-MF ${_OBJDIR}/${_s:R}.d} -c ${.CURDIR}/src/${_s} -o ${.TARGET}
.  elif !empty(_CXX_EXTS:M${_s:E})
${_OBJDIR}/${_s:R}.o: ${.CURDIR}/src/${_s} ${_INPUTS_HASH_FILE}
	${CXX} ${CXXFLAGS} ${_DEP_CFLAGS} ${_DEP_CFLAGS:D-MF ${_OBJDIR}/${_s:R}.d} -c ${.CURDIR}/src/${_s} -o ${.TARGET}
.  elif ${_s:E} == "y"
${_OBJDIR}/${_s:R}.c: ${.CURDIR}/src/${_s}
	${YACC} ${YFLAGS} -d -o ${.TARGET} ${.ALLSRC}
	@if [ -f y.tab.h ]; then mv y.tab.h ${_OBJDIR}/${_s:R}.h; fi
${_OBJDIR}/${_s:R}.o: ${_OBJDIR}/${_s:R}.c ${_INPUTS_HASH_FILE}
	${CC} ${CFLAGS} ${_DEP_CFLAGS} ${_DEP_CFLAGS:D-MF ${_OBJDIR}/${_s:R}.d} -c ${_OBJDIR}/${_s:R}.c -o ${.TARGET}
.  elif ${_s:E} == "l"
${_OBJDIR}/${_s:R}.c: ${.CURDIR}/src/${_s}
	${LEX} ${LFLAGS} -o ${.TARGET} ${.ALLSRC}
${_OBJDIR}/${_s:R}.o: ${_OBJDIR}/${_s:R}.c ${_INPUTS_HASH_FILE}
	${CC} ${CFLAGS} ${_DEP_CFLAGS} ${_DEP_CFLAGS:D-MF ${_OBJDIR}/${_s:R}.d} -c ${_OBJDIR}/${_s:R}.c -o ${.TARGET}
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

all: _check_inputs_hash _create_dirs ${_BINOUT}
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
	${_CCLINK} -o ${.TARGET} ${OBJS} ${LDFLAGS}

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


.include "${BMK_MKDIR}/mk.test.mk"

_LOCAL_MK_PHASE = local
.include "${BMK_MKDIR}/mk.local.mk"

BMK_HELP_ROLE = prog
.include "${BMK_MKDIR}/mk.help.mk"

.PHONY: all clean help copy-up _create_dirs help
.endif

