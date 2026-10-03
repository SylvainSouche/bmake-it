# mk.constraints.mk -- where this module/framework is built
# (platform-toolchain-constraints-dec). Evaluates PLATFORMS= and
# TOOLCHAINS= (declared in the including makefile, before its .include)
# against the selected TARGET/TARGET_ARCH/TOOLCHAIN and sets:
#   _BMK_BUILD     yes | skip   (an error stops the parse instead)
#   _BMK_SKIP_MSG  why, for the one informational line
# Included by mk.prog.mk, mk.lib.mk and mk.framework.mk right after the
# "pre" hooks and BEFORE any import resolution or REQUIRES= check, so an
# excluded module never fails on something only its own platform needs.
# Errors and warnings are suppressed for a -V query, clean and help, the
# same guard REQUIRES= uses: asking for a variable or cleaning must never
# fail because of where something is NOT built.
# @impl 0f87-6ac0-d891-3000

_BMK_BUILD = yes
_BMK_SKIP_MSG =
_CX_REPORT = yes
.if !empty(.MAKEFLAGS:M-V*) || make(clean) || make(help)
_CX_REPORT = no
.endif

.if (defined(PLATFORMS) && !empty(PLATFORMS)) || (defined(TOOLCHAINS) && !empty(TOOLCHAINS))
_PX_STATE = build
_PX_MSG =
_TX_STATE = build
_TX_MSG =
.  if defined(PLATFORMS) && !empty(PLATFORMS)
_CX_AXIS = PLATFORMS
_CX_LIST = ${PLATFORMS}
_CX_TNAMES = ${TARGET} ${TARGET}_${TARGET_ARCH}
_CX_HIER = yes
.    include "${BMK_MKDIR}/mk.constraint-axis.mk"
_PX_STATE := ${_CX_STATE}
_PX_MSG := ${_CX_MSG}
.  endif
.  if defined(TOOLCHAINS) && !empty(TOOLCHAINS)
_CX_AXIS = TOOLCHAINS
_CX_LIST = ${TOOLCHAINS}
_CX_TNAMES = ${TOOLCHAIN}
_CX_HIER = no
.    include "${BMK_MKDIR}/mk.constraint-axis.mk"
_TX_STATE := ${_CX_STATE}
_TX_MSG := ${_CX_MSG}
.  endif

# An error on either axis wins over a skip on the other.
.  if ${_PX_STATE} == "error" || ${_TX_STATE} == "error"
.    if ${_PX_STATE} == "error"
_CX_ERR := ${_PX_MSG}
.    else
_CX_ERR := ${_TX_MSG}
.    endif
.    if ${_CX_REPORT} == "yes"
.      error "${.CURDIR:T}: ${_CX_ERR} -- choosing this combination is an error (a '!' entry); see PLATFORMS=/TOOLCHAINS= in the makefile"
.    endif
.  elif ${_PX_STATE} == "skip" || ${_TX_STATE} == "skip"
_BMK_BUILD = skip
.    if ${_PX_STATE} == "skip"
_BMK_SKIP_MSG := ${_PX_MSG}
.    else
_BMK_SKIP_MSG := ${_TX_MSG}
.    endif
.  endif
.endif
