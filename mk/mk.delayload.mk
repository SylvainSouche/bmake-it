# mk.delayload.mk -- delay loading of shared libraries (Windows linkers).
#
# delay-load-default-by-library-req: a shared library's module declares whether
# it is loaded at the first call into it, not when the program starts
# (DELAYLOAD=yes|no, default no); a module linking it overrides that for itself
# (DELAYLOAD.<lib>=yes|no). The library's module writes lib<LIB>.delayload
# beside lib<LIB>.linkdeps: "<default> <dll name, or -> <exports data: 0 1 ?>".
#
# Read by mk.lib.mk and mk.prog.mk once _LIB_SEARCH_DIRS is known, before their
# LDFLAGS += -l<lib> loop.
#
# How, by linker (delay-load-windows-toolchains-obs, delay-load-msvc-obs):
#   msvc  cl.exe, clang-cl: /DELAYLOAD:<dll> and delayimp.lib
#         (-Wl,--delayload=<dll>, translated by msvc-cc-wrapper.sh)
#   lld   mingw-w64, ld.lld: -Wl,--delayload=<dll>
#   gnu   mingw-w64, GNU ld: lib<lib>.delay.a, made by dlltool -y from the DLL's
#         .def, in place of the import library. GNU ld reads garbage for a data
#         export instead of refusing it (delay-load-data-export-obs), so the
#         .def's DATA marks are checked here on every linker that has one.
#   none  everything else: ELF and Mach-O have no such thing, and Cygwin output
#         is unreliable (delay-load-windows-toolchains-obs). A library's default
#         has no effect; a consumer's explicit yes gets a note at its link.
# @impl 7854-6ae5-cb17-4ec0
.if !defined(_BMK_DELAYLOAD_MK)
_BMK_DELAYLOAD_MK = yes

_DELAYLOAD_KIND = none
.if ${TARGET} == "win"
.  if ${_BMK_MSVC_ABI} == "yes"
_DELAYLOAD_KIND = msvc
.  elif ${_BMK_WIN_MINGW:Uno} == "yes"
.    if ${TOOLCHAIN} == "llvm" && !empty(_MINGW_LLD:U)
_DELAYLOAD_KIND = lld
.    else
_DELAYLOAD_KIND = gnu
.    endif
.  endif
.endif

DELAYLOAD ?= no
.if ${DELAYLOAD} != "yes" && ${DELAYLOAD} != "no"
.  error "DELAYLOAD=${DELAYLOAD}: expected yes or no"
.endif

_DELAYLOAD_NOTES =
_DELAYLOAD_ERRORS =
_DELAYLOAD_FILES =
.for _l in ${LIBS}
.  if defined(DELAYLOAD.${_l})
.    if ${DELAYLOAD.${_l}} != "yes" && ${DELAYLOAD.${_l}} != "no"
.      error "DELAYLOAD.${_l}=${DELAYLOAD.${_l}}: expected yes or no"
.    endif
.    if defined(LIB) && ${LIB_SHARED:Uno} != "YES"
.      error "DELAYLOAD.${_l}=${DELAYLOAD.${_l}} on the static library ${LIB}: a static library links nothing, so there is nothing to delay here -- set it on the program or shared library that links ${LIB}"
.    endif
.  endif
.  if ${_DELAYLOAD_KIND} == "none"
.    if ${DELAYLOAD.${_l}:Uno} == "yes"
_DELAYLOAD_NOTES += ${_l}
.    endif
.  else
# (the directories as a dependency line may name them, relative to the module
# directory: _DELAYLOAD_FILES are make prerequisites of the link)
.    for _d in ${_LIB_SEARCH_DIRS_DEP}
.      if !defined(_DELAY_INFO.${_l}) && exists(${_d:${_BMK_DEC}}/lib${_l}.delayload)
_DELAY_INFO.${_l} != cat ${_d:${_BMK_DEC}:Q}/lib${_l}.delayload
_DELAY_DIR.${_l} = ${_d:${_BMK_DEC}}
_DELAYLOAD_FILES += ${_d:${_BMK_DEC}}/lib${_l}.delayload
.      endif
.    endfor
.    if defined(_DELAY_INFO.${_l})
_DELAY_ON.${_l} = ${DELAYLOAD.${_l}:U${_DELAY_INFO.${_l}:[1]}}
.      if ${_DELAY_ON.${_l}} == "yes"
.        if ${_DELAY_INFO.${_l}:[2]} == "-"
_DELAYLOAD_ERRORS += ${_l}
_DELAY_ERR.${_l} = library ${_l} has no DLL in ${_DELAY_DIR.${_l}}: only a DLL can be delay-loaded
.        elif ${_DELAY_INFO.${_l}:[3]} == "1"
_DELAYLOAD_ERRORS += ${_l}
_DELAY_ERR.${_l} = ${_DELAY_INFO.${_l}:[2]} exports data, and a DLL that exports data cannot be delay-loaded -- export functions only, or set DELAYLOAD.${_l}=no
.        elif ${_DELAYLOAD_KIND} == "gnu"
.          if exists(${_DELAY_DIR.${_l}}/lib${_l}.delay.a)
_DELAY_LIB.${_l} = ${_l}.delay
.          else
_DELAYLOAD_ERRORS += ${_l}
_DELAY_ERR.${_l} = there is no lib${_l}.delay.a in ${_DELAY_DIR.${_l}}: GNU ld needs one, made from a .def that Bmake It has only for a DLL it built (an imported DLL needs ld.lld or the MSVC linker), and from ${_MINGW_TRIPLE}-dlltool
.          endif
.        else
LDFLAGS += -Wl,--delayload=${_DELAY_INFO.${_l}:[2]}
.        endif
.      endif
.    elif ${DELAYLOAD.${_l}:Uno} == "yes"
_DELAYLOAD_ERRORS += ${_l}
_DELAY_ERR.${_l} = no lib${_l}.delayload in ${_LIB_SEARCH_DIRS:${_BMK_DEC}}: is ${_l} a library module of this workspace? For a system DLL, give the linker its flags in LDFLAGS
.    endif
.  endif
.endfor

# What each link rule runs first. A misspelt DELAYLOAD.<lib> would otherwise do
# nothing without a word, and bmake cannot list variables: the module's own
# makefile is searched, and only when it links. Not the hooks of mk/: a hook can
# set one for every module of a framework, and not all of them link that library.
_DELAYLOAD_NAMED = for _v in $$(grep -ho 'DELAYLOAD\.[A-Za-z0-9_+-]*' ${.CURDIR:Q}/${MAKEFILE:T:Umakefile:Q} /dev/null 2>/dev/null | sort -u); do \
		case " ${LIBS} " in \
			*" $${_v\#DELAYLOAD.} "*) ;; \
			*) echo "error: $$_v is set in ${_CURNAME}, but $${_v\#DELAYLOAD.} is not in its LIBS= (${LIBS})" >&2; exit 1 ;; \
		esac; \
	done

.endif
