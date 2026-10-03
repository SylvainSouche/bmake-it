# mk.constraint-axis.mk -- evaluates ONE constraint axis (PLATFORMS= or
# TOOLCHAINS=) for the selected target. Internal: included twice by
# mk.constraints.mk with these inputs set:
#   _CX_AXIS    PLATFORMS | TOOLCHAINS (used in messages)
#   _CX_LIST    the list as declared
#   _CX_TNAMES  the names the selected target answers to, least to most
#               specific ("linux linux_arm64"; "gcc")
#   _CX_HIER    yes if an os_arch entry is a subset of its os (platforms)
#   _CX_REPORT  yes to emit .error/.warning (no for -V, clean, help)
# Outputs: _CX_STATE (build | skip | error) and _CX_MSG.
#
# Entry grammar [!][-]name (platform-list-grammar-req): plain = only these,
# -name = not these, a leading ! makes the entry loud (an error instead of
# a skip). Order (platform-constraint-evaluation-req): loud negative, quiet
# negative, then the positive set. Validity (platform-list-validity-req):
# positive and negative entries only mix when each negative is a subset of
# a positive entry.
# @impl 0f87-6ac0-d891-3000

_CX_STATE = build
_CX_MSG =
_CX_POS =
_CX_NEGQ =
_CX_NEGL =
_CX_POSLOUD = no
.for _e in ${_CX_LIST}
.  if ${_e:M!-*}
_CX_NEGL += ${_e:S/^!-//}
.  elif ${_e:M!*}
_CX_POS += ${_e:S/^!//}
_CX_POSLOUD = yes
.  elif ${_e:M-*}
_CX_NEGQ += ${_e:S/^-//}
.  else
_CX_POS += ${_e}
.  endif
.endfor
_CX_SELECTED = ${_CX_TNAMES:[-1]}

# --- validity ---------------------------------------------------------
.if !empty(_CX_POS) && (!empty(_CX_NEGQ) || !empty(_CX_NEGL))
.  if ${_CX_HIER} != "yes"
.    if ${_CX_REPORT} == "yes"
.      error "${.CURDIR:T}: ${_CX_AXIS}=${_CX_LIST}: positive and negative entries cannot be mixed here (these names have no hierarchy, so no negative entry can be a subset of a positive one)"
.    endif
.  else
.    for _n in ${_CX_NEGQ} ${_CX_NEGL}
_cx_ok = no
.      for _p in ${_CX_POS:M*}
_cx_a = ${_n:C/_.*//}
_cx_b = ${_n:M*_*}
_cx_c = ${_p:M*_*}
.        if "${_cx_a}" == "${_p}" && !empty(_cx_b) && empty(_cx_c)
_cx_ok = yes
.        endif
.      endfor
.      if ${_cx_ok} != "yes" && ${_CX_REPORT} == "yes"
.        error "${.CURDIR:T}: ${_CX_AXIS}=${_CX_LIST}: -${_n} is not a subset of any positive entry (${_CX_POS:M*}); a negative entry is only allowed beside positive ones when it narrows one, e.g. 'linux -linux_arm64'"
.      endif
.    endfor
.  endif
.endif

# --- unknown names only warn: a typo must not fail a future platform ----
.if ${_CX_REPORT} == "yes"
.  for _x in ${_CX_POS:M*} ${_CX_NEGQ} ${_CX_NEGL}
.    if ${_CX_HIER} == "yes"
_cx_os = ${_x:C/_.*//}
_cx_known = no
.      for _kn in macos linux freebsd netbsd win
.        if "${_cx_os}" == "${_kn}"
_cx_known = yes
.        endif
.      endfor
.      if ${_cx_known} != "yes"
.        warning "${.CURDIR:T}: ${_CX_AXIS}: unknown platform '${_x}' (known: macos linux freebsd netbsd win, optionally _<arch>)"
.      endif
.    else
.      if !exists(${BMK_MKDIR}/mk.toolchain.${_x}.mk)
.        warning "${.CURDIR:T}: ${_CX_AXIS}: unknown toolchain '${_x}'"
.      endif
.    endif
.  endfor
.endif

# --- evaluation ---------------------------------------------------------
.for _n in ${_CX_NEGL}
_cx_t = ${_CX_TNAMES:M${_n}}
.  if ${_CX_STATE} == "build" && !empty(_cx_t)
_CX_STATE = error
_CX_MSG = ${_CX_AXIS} excludes ${_CX_SELECTED} (!-${_n})
.    if defined(REASON.${_n})
_CX_MSG += -- ${REASON.${_n}}
.    endif
.  endif
.endfor
.for _n in ${_CX_NEGQ}
_cx_t = ${_CX_TNAMES:M${_n}}
.  if ${_CX_STATE} == "build" && !empty(_cx_t)
_CX_STATE = skip
_CX_MSG = ${_CX_AXIS} excludes ${_CX_SELECTED} (-${_n})
.    if defined(REASON.${_n})
_CX_MSG += -- ${REASON.${_n}}
.    endif
.  endif
.endfor
.if ${_CX_STATE} == "build" && !empty(_CX_POS)
_cx_hit = no
.  for _p in ${_CX_POS:M*}
_cx_t = ${_CX_TNAMES:M${_p}}
.    if !empty(_cx_t)
_cx_hit = yes
.    endif
.  endfor
.  if ${_cx_hit} != "yes"
.    if ${_CX_POSLOUD} == "yes"
_CX_STATE = error
.    else
_CX_STATE = skip
.    endif
_CX_MSG = ${_CX_AXIS}=${_CX_POS:M*} does not include ${_CX_SELECTED}
.    for _p in ${_CX_POS:M*}
.      if defined(REASON.${_p})
_CX_MSG += -- ${REASON.${_p}}
.      endif
.    endfor
.  endif
.endif
