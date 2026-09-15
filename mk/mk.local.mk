# mk.local.mk — look for and include per-level local-customization hooks
# (local-mk-hook-files-and-cascade-order-req). Not included directly by a
# makefile -- each role file sets _LOCAL_MK_DIRS (its own level's visible
# mk/ directories, outer-to-inner) and _LOCAL_MK_PHASE (pre | local), then
# .includes this file. Six conventional names are checked per directory:
# <phase>.mk (unconditional), <phase>.${TOOLCHAIN}.mk, <phase>.${TARGET}.mk.
# ALL matching levels are included, not just the most specific -- that's
# the cascade, done by the caller repeating _LOCAL_MK_DIRS outer-to-inner.
#
# TARGET/TOOLCHAIN must already be resolved (i.e. mk.common.mk already
# .included) before the "pre" phase fires, so the conditional filenames
# are meaningful -- "pre" therefore means "before the ROLE file's own
# defaults", not before mk.common.mk's foundational TARGET/TOOLCHAIN
# resolution, which every level needs regardless.
# @impl 0f87-6aa9-0275-667f

.for _d in ${_LOCAL_MK_DIRS}
.  if exists(${_d}/${_LOCAL_MK_PHASE}.mk)
.    include "${_d}/${_LOCAL_MK_PHASE}.mk"
.  endif
.  if exists(${_d}/${_LOCAL_MK_PHASE}.${TOOLCHAIN}.mk)
.    include "${_d}/${_LOCAL_MK_PHASE}.${TOOLCHAIN}.mk"
.  endif
.  if exists(${_d}/${_LOCAL_MK_PHASE}.${TARGET}.mk)
.    include "${_d}/${_LOCAL_MK_PHASE}.${TARGET}.mk"
.  endif
.endfor
