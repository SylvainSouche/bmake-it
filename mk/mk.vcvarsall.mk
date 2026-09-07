# mk.vcvarsall.mk — replicates vcvarsall.bat's environment discovery in
# pure bmake, so TOOLCHAIN=msvc works from a plain Cygwin shell without
# requiring a Developer Command Prompt or a manual vcvarsall.bat call
# first. Included by mk.toolchain.msvc.mk; sets _MSVC_BIN (Cygwin-style,
# for PATH), _MSVC_INCLUDE and _MSVC_LIB (Windows-style, semicolon-joined,
# for the INCLUDE/LIB env vars cl.exe/link.exe themselves read).
#
# Scoped to the same -V/clean guard as the cross-compile checks elsewhere
# in this project: none of this is needed for a query or a clean, and
# vswhere.exe + a handful of file reads is not free at every parse.

.if !defined(_MK_VCVARSALL_MK_)
_MK_VCVARSALL_MK_ = 1

.if empty(.MAKEFLAGS:M-V*) && !make(clean)

# bmake's own exists()/file-read builtins need the Cygwin/POSIX form of a
# path (backslash-form Windows paths are taken as literal characters, not
# separators, by bmake's own stat() calls) -- only vswhere.exe's own
# -property output (already Windows-style, since it's a native program
# reporting Windows paths) needs the reverse treatment, handled below.
_VSWHERE = /cygdrive/c/Program Files (x86)/Microsoft Visual Studio/Installer/vswhere.exe
.  if !exists(${_VSWHERE})
.    error "TOOLCHAIN=msvc: vswhere.exe not found at '${_VSWHERE}' -- no Visual Studio Installer-managed product (VS2017+, including Build Tools) appears to be installed."
.  endif

# vswhere itself is a native Windows exe; -latest picks the newest
# installed instance if more than one product/edition is present.
_VS_ROOT != "${_VSWHERE}" -latest -products '*' -property installationPath 2>/dev/null | tr -d '\r'
.  if empty(_VS_ROOT)
.    error "TOOLCHAIN=msvc: vswhere.exe found no installed Visual Studio product with the C++ build tools workload."
.  endif

# The toolset version vcvarsall.bat itself would pick with no explicit
# version argument -- same file it reads.
_MSVC_VER != cat "${_VS_ROOT}\VC\Auxiliary\Build\Microsoft.VCToolsVersion.default.txt" 2>/dev/null | tr -d '\r\n'
.  if empty(_MSVC_VER)
.    error "TOOLCHAIN=msvc: could not read the default MSVC toolset version from '${_VS_ROOT}\\VC\\Auxiliary\\Build\\Microsoft.VCToolsVersion.default.txt'."
.  endif

# MSVC's own host/target architecture names, mapped from this project's.
.  if ${_HOST_ARCH_LABEL} == "amd64"
_MSVC_HOST_ARCH = x64
.  elif ${_HOST_ARCH_LABEL} == "arm64"
_MSVC_HOST_ARCH = arm64
.  else
_MSVC_HOST_ARCH = ${_HOST_ARCH_LABEL}
.  endif

.  if ${TARGET_ARCH} == "amd64"
_MSVC_TARGET_ARCH = x64
.  elif ${TARGET_ARCH} == "arm64"
_MSVC_TARGET_ARCH = arm64
.  elif ${TARGET_ARCH} == "x86"
_MSVC_TARGET_ARCH = x86
.  else
.    error "TOOLCHAIN=msvc: unrecognized TARGET_ARCH=${TARGET_ARCH} -- MSVC understands x64, arm64, x86."
.  endif

_MSVC_TOOLROOT = ${_VS_ROOT}\VC\Tools\MSVC\${_MSVC_VER}
# PATH needs the Cygwin-style form of the host-arch/target-arch bin dir.
_MSVC_BIN != cygpath -u "${_MSVC_TOOLROOT}\bin\Host${_MSVC_HOST_ARCH}\${_MSVC_TARGET_ARCH}"

# Windows SDK: highest-versioned subdirectory under Include/ (matches
# vcvarsall.bat's own "latest installed SDK" default when none is pinned).
_SDK_ROOT = C:\Program Files (x86)\Windows Kits\10
_SDK_VER != ls "$$(cygpath -u '${_SDK_ROOT}\Include')" 2>/dev/null | sort -V | tail -1
.  if empty(_SDK_VER)
.    error "TOOLCHAIN=msvc: no Windows SDK found under '${_SDK_ROOT}\\Include' -- the C++ workload should have installed one alongside MSVC."
.  endif

# INCLUDE/LIB are consumed directly by cl.exe/link.exe (native Windows
# programs) -- Windows-style, semicolon-joined, not cygpath'd.
_MSVC_INCLUDE = ${_MSVC_TOOLROOT}\include;${_SDK_ROOT}\Include\${_SDK_VER}\ucrt;${_SDK_ROOT}\Include\${_SDK_VER}\shared;${_SDK_ROOT}\Include\${_SDK_VER}\um;${_SDK_ROOT}\Include\${_SDK_VER}\winrt
_MSVC_LIB     = ${_MSVC_TOOLROOT}\lib\${_MSVC_TARGET_ARCH};${_SDK_ROOT}\Lib\${_SDK_VER}\ucrt\${_MSVC_TARGET_ARCH};${_SDK_ROOT}\Lib\${_SDK_VER}\um\${_MSVC_TARGET_ARCH}

.endif # -V/clean guard

.endif # _MK_VCVARSALL_MK_
