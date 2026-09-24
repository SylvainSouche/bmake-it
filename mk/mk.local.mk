# mk.local.mk — look for and include per-level local-customization hooks
# (local-mk-hook-files-and-cascade-order-req). Not included directly by a
# makefile -- each role file sets _LOCAL_MK_DIRS (its own level's visible
# mk/ directories, outer-to-inner) and _LOCAL_MK_PHASE (pre | local), then
# .includes this file. Four conventional names are checked per directory:
# <phase>.mk (unconditional), <phase>.${TOOLCHAIN}.mk, <phase>.${TARGET}.mk,
# <phase>.${TARGET}_${TARGET_ARCH}.mk (same naming as share/<os>_<arch>,
# for a path that differs by arch on one OS -- Homebrew's /opt/homebrew on
# arm64 vs /usr/local on amd64, or a cross sysroot -- local-mk-arch-
# variant-req). No combined toolchain+target_arch filename: the realistic
# need is covered by target_arch alone, and the separate .${TOOLCHAIN}.mk
# variant already covers toolchain overrides independently.
# ALL matching levels are included, not just the most specific -- that's
# the cascade, done by the caller repeating _LOCAL_MK_DIRS outer-to-inner.
#
# TARGET/TOOLCHAIN must already be resolved (i.e. mk.common.mk already
# .included) before the "pre" phase fires, so the conditional filenames
# are meaningful -- "pre" therefore means "before the ROLE file's own
# defaults", not before mk.common.mk's foundational TARGET/TOOLCHAIN
# resolution, which every level needs regardless.
# @impl 0f87-6aa9-0275-667f
# @impl 0f87-6ab5-88d0-e665

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
.  if exists(${_d}/${_LOCAL_MK_PHASE}.${TARGET}_${TARGET_ARCH}.mk)
.    include "${_d}/${_LOCAL_MK_PHASE}.${TARGET}_${TARGET_ARCH}.mk"
.  endif
.endfor
