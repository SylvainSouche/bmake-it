# mk.resolved.mk -- stop the build when a setting mk.common.mk reads at parse
# time was changed after it ran (late-setting-error-req). Included by the role
# files right after the "pre" hook phase, so it sees a module body that came
# after an early `.include <mk.common.mk>` and any mk/pre*.mk hook. Without
# this, `.include <mk.common.mk>` first and then `TOOLCHAIN=gcc` leaves CC at
# clang with no message at all; OPENMP= and SANITIZE= are ignored the same way.
# Setting the same value again is accepted. The ways out are the two the
# message names: before the include, or on the command line / environment.
# @impl 0f87-6aea-ddec-454d
.for _v in ${_BMK_PARSE_TIME_VARS}
.  if "${${_v}:U}" != "${_BMK_RESOLVED.${_v}}"
.    error "${_v}=${${_v}:U} was set after mk.common.mk had already resolved ${_v}=${_BMK_RESOLVED.${_v}} -- a module makefile or a mk/pre*.mk hook changed it too late to have any effect (CC, flags and the build directory were already chosen). Set ${_v} before the .include of mk.common.mk, or on the command line (bmake ${_v}=...), or in the environment"
.  endif
.endfor
