# mk.searchpaths.mk -- where a module finds headers and libraries: its own
# include/, its framework's, those of the frameworks its framework lists in
# PREREQS=, and the libraries LIBS= names (-l flags, run paths, link
# dependencies, and the library files a relink waits for).
# Included by mk.prog.mk and mk.lib.mk, after _FWDIR is set.
#
# Two kinds of path, for two kinds of use (path-characters-supported-req):
#  - a path in a command (-I, -L, -rpath) is written for the shell (:Q), with
#    names and directories carried as encoded words in lists and in variable
#    names (see "Names and paths in word lists" in mk.common.mk);
#  - a path in a dependency line -- a header the compiler lists in a .d file, a
#    library a relink waits for -- cannot hold a space or a parenthesis, which
#    make reads as a word end or an archive member. Those are named relative to
#    the module directory (bmake always runs there), so no part of the
#    workspace's path is in them, and a prerequisite framework whose name or
#    place has a space or parenthesis in it is reached through a link in the
#    module's own build directory, named with its encoded name
#    (build/<key>/prereqs/<name>), which has neither.
# @impl 0f87-6af0-c37a-26d0

# --- headers: the module's own, then its framework's -------------------------
.if exists(${.CURDIR}/include)
CFLAGS   += -Iinclude
CXXFLAGS += -Iinclude
.endif
.if exists(${_FWDIR}/local/include)
CFLAGS   += -I../local/include
CXXFLAGS += -I../local/include
.endif
.if exists(${_FWDIR}/include)
CFLAGS   += -I../include
CXXFLAGS += -I../include
.endif
.if exists(${_FWDIR}/${BUILD_ROOT}/include)
CFLAGS   += -I../${BUILD_ROOT}/include
CXXFLAGS += -I../${BUILD_ROOT}/include
.endif

# --- the frameworks named in PREREQS= ----------------------------------------
# _PREREQS: their names (encoded words); _PREREQ_BASE.<name>: the directory that
# holds each (encoded). _PREREQ_DEP.<name>: how a dependency line and the
# compiler's -I name it, relative to this module directory or through the link.
.if exists(${_FWDIR}/makefile)
# ${MAKE}, not a command named bmake: NetBSD has no bmake (its make is /usr/bin/make),
# and 2>/dev/null || true would hide the failure as an empty PREREQS.
# @impl 0f87-6ad7-d974-4a81
_PREREQS != ${MAKE} -f ${_FWDIR:Q}/makefile -V '$${_PREREQS_E}' 2>/dev/null || true
.  for _p in ${_PREREQS}
_pn := ${_p:${_BMK_DEC}}
# REQ-headers-resolved-from-source-req: a PREREQS framework is resolved
# first within the current workspace, then falling back through PARENT_WS
# workspaces in declared order if not found locally.
# @impl 0f87-6a98-5e47-0c71
.    if exists(${_FWDIR}/../${_pn})
_PREREQ_BASE.${_p} = ${_FWDIR:${_BMK_ENCW}}/..
_PREREQ_DEP.${_p} = ../../${_p}
.    else
.      for _pws in ${_PARENT_WS_E}
.        if !defined(_PREREQ_BASE.${_p}) && exists(${_pws:${_BMK_DEC}}/${_pn})
_PREREQ_BASE.${_p} = ${_pws}
_PREREQ_DEP.${_p} = ${_pws}/${_p}
.        endif
.      endfor
.    endif
# a name or a place make cannot write in a dependency line: reach it through a link
.    if defined(_PREREQ_DEP.${_p}) && (!empty(_PREREQ_DEP.${_p}:M*%2[089]*) || !empty(_p:M*%2[089]*))
_PREREQ_DEP.${_p} = ${BUILD_ROOT}/prereqs/${_p:${_BMK_ENCW}}
_PREREQ_LINKED += ${_p}
.    endif
.    if defined(_PREREQ_BASE.${_p})
_pb := ${_PREREQ_BASE.${_p}:${_BMK_DEC}}
# public-headers-system-req (D3): a framework may opt its whole public
# header surface into -isystem for consumers, typically because it
# wraps/vendors third-party code -- an explicit, framework-level
# declaration, not inferred from any module's own WARN= setting.
.      if exists(${_pb}/${_pn}/makefile)
_PREREQ_SYS.${_p} != ${MAKE} -f ${_pb:Q}/${_pn:Q}/makefile -V PUBLIC_HEADERS_SYSTEM 2>/dev/null || true
.      endif
.      if ${_PREREQ_SYS.${_p}:Uno} == "yes"
_INCFLAG.${_p} = -isystem
.      else
_INCFLAG.${_p} = -I
.      endif
.      if exists(${_pb}/${_pn}/include)
CFLAGS   += ${_INCFLAG.${_p}}${_PREREQ_DEP.${_p}:${_BMK_DEC}:Q}/include
CXXFLAGS += ${_INCFLAG.${_p}}${_PREREQ_DEP.${_p}:${_BMK_DEC}:Q}/include
.      endif
.      if exists(${_pb}/${_pn}/${BUILD_ROOT}/include)
CFLAGS   += ${_INCFLAG.${_p}}${_PREREQ_DEP.${_p}:${_BMK_DEC}:Q}/${BUILD_ROOT}/include
CXXFLAGS += ${_INCFLAG.${_p}}${_PREREQ_DEP.${_p}:${_BMK_DEC}:Q}/${BUILD_ROOT}/include
.      endif
.      if exists(${_pb}/${_pn}/${BUILD_ROOT}/lib)
LDFLAGS  += -L${_pb:Q}/${_pn:Q}/${BUILD_ROOT}/lib
.      endif
.    endif
.  endfor
.endif

# The links (recipe time, before anything is compiled): one per prerequisite
# framework that needs one.
_create_prereq_links:
.for _p in ${_PREREQ_LINKED:O:u}
	@mkdir -p ${BUILD_ROOT}/prereqs && ln -sfn ${_PREREQ_BASE.${_p}:${_BMK_DEC}:Q}/${_p:${_BMK_DEC}:Q} ${BUILD_ROOT}/prereqs/${_p}
.endfor
	@:

# --- libraries ----------------------------------------------------------------
# prog-only-framework-ld-warning-fix-req: guarded the same way the
# PREREQS= loop just above already is -- a framework holding only a
# PROG (no LIB module at all) never creates its own build/<KEY>/lib/,
# so an unconditional -L here produced a harmless but noisy
# `ld: warning: search path ... not found` on every single link (found
# in real use, Viewer: a program-only framework). A sibling LIB module
# in the SAME framework, when one exists, has already built and
# copied-up by the time this module's own makefile parses (modules
# build in order, one fully completing before the next starts), so
# this dir reliably exists whenever it's actually needed.
# @impl 0f87-6abe-3f50-b644
.if exists(${_FWDIR}/${BUILD_ROOT}/lib)
LDFLAGS += -L../${BUILD_ROOT}/lib
.endif
# _LIB_SEARCH_DIRS: the directories a library may be in, as encoded words,
# absolute (a run path, a -L in a .linkdeps file read from elsewhere).
# _LIB_SEARCH_DIRS_DEP: the same directories as a dependency line may name them.
_LIB_SEARCH_DIRS = ${_FWDIR:${_BMK_ENCW}}/${BUILD_ROOT}/lib
_LIB_SEARCH_DIRS_DEP = ../${BUILD_ROOT}/lib
.for _p in ${_PREREQS}
.  if defined(_PREREQ_BASE.${_p}) && exists(${_PREREQ_BASE.${_p}:${_BMK_DEC}}/${_p:${_BMK_DEC}}/${BUILD_ROOT}/lib)
_LIB_SEARCH_DIRS += ${_PREREQ_BASE.${_p}}/${_p}/${BUILD_ROOT}/lib
_LIB_SEARCH_DIRS_DEP += ${_PREREQ_DEP.${_p}}/${BUILD_ROOT}/lib
.  endif
.endfor
# the same, for a shell loop: decoded and quoted
_LIB_SEARCH_DIRS_SH = ${_LIB_SEARCH_DIRS:@_w@${_w:${_BMK_DEC}:Q}@}

# Runtime search path for LIBS= -- link-time -L/-l success doesn't imply
# the resulting binary can find the shared lib at run time (see mk.lib.mk
# for the same reasoning). No rpath concept on Windows.
# @impl 0f87-6aa9-448d-537c
.if ${TARGET} != "win"
.  for _d in ${_LIB_SEARCH_DIRS}
LDFLAGS += -Wl,-rpath,${_d:${_BMK_DEC}:Q}
.  endfor
.endif

# @impl 0f87-6a98-76c2-a96e
# import-link-transitivity-req: -l${_l} alone only satisfies THIS
# module's own direct reference -- ${_l}'s own transitive deps (its
# lib${_l}.linkdeps, written by that module itself, whether compiled or
# imported) are appended too, so a consumer never has to list them by
# hand. No found-guard against the same name resolving in more than one
# _LIB_SEARCH_DIRS entry -- duplicate -l/-L flags are harmless.
# @impl 0f87-6ab5-8e46-cfb1
.include "${BMK_MKDIR}/mk.delayload.mk"
.for _l in ${LIBS}
LDFLAGS += -l${_DELAY_LIB.${_l}:U${_l}}
.  for _d in ${_LIB_SEARCH_DIRS}
.    if exists(${_d:${_BMK_DEC}}/lib${_l}.linkdeps)
_LINKDEPS.${_l} != cat ${_d:${_BMK_DEC}:Q}/lib${_l}.linkdeps
LDFLAGS += ${_LINKDEPS.${_l}}
.    endif
.  endfor
.endfor

# relink-on-libs-change-req: each LIBS= entry's *actual resolved file*
# (not just its -l/-L flags) is a real make prerequisite of the link, so a
# library rebuilt elsewhere -- including a PREREQS=-visible one in
# another framework -- triggers a genuine relink here, not just a link-
# time existence check (found empirically: a stale binary kept passing
# because nothing in the prerequisite graph ever changed when a cross-
# framework static library did). Empty when not yet built is fine --
# the existing existence-check loop below still gives its own clear
# error for that case; this only matters once the file DOES exist.
# The file is named as a dependency line may (see above); _LIB_FILE_DIR.<lib>
# is the directory it was found in, absolute and real.
# @impl 0f87-6aba-a303-153e
# @impl 7854-6ad0-fb85-c2c6
_LIBS_FILES =
.for _l in ${LIBS}
_LIB_FILE.${_l} != for _d in ${_LIB_SEARCH_DIRS_DEP:@_w@${_w:${_BMK_DEC}:Q}@}; do \
	for _f in ${_LIB_FILE_FORMS:S/@/${_l}/g}; do \
		if [ -f "$$_d/$$_f" ]; then echo "$$_d/$$_f"; break 2; fi; \
	done; \
done
_LIB_FILE_DIR.${_l} != f=${_LIB_FILE.${_l}:Q}; if [ -n "$$f" ]; then cd "$$(dirname "$$f")" && pwd -P; fi
_LIBS_FILES += ${_LIB_FILE.${_l}}
.endfor
