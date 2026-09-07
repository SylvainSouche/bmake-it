# mk.toolchain.llvm.mk — LLVM/clang toolchain bundle
# Sets CC/CXX/LD/AR/AS as a coherent set for the selected TARGET/TARGET_ARCH.
# (REQ-toolchain-mk-must-set-explicit-cc-paths-req-v5)

.if !defined(_MK_TOOLCHAIN_LLVM_MK_)
_MK_TOOLCHAIN_LLVM_MK_ = 1

# Host-native defaults (when TARGET matches host).
# REQ-toolchain-mk-must-set-explicit-cc-paths-req-v5: search PATH, then a
# list of common install prefixes -- never a single hardcoded absolute path.
# clang commonly lives outside /usr/bin (MacPorts /opt/local/bin, pkgsrc
# /usr/pkg/bin, Homebrew, ...); a single-path check silently falls through
# to plain cc/c++ there, which may be a different compiler entirely. Fail
# loudly instead of silently building with the wrong toolchain.
#
# Bare `!defined(CC)` is not a safe guard here: bmake's own sys.mk
# unconditionally soft-assigns `CC?=cc` before any of our files are parsed
# (confirmed on real NetBSD -- /usr/share/mk/sys.mk:28), so CC is *always*
# already "defined" by the time this file runs, regardless of TOOLCHAIN=.
# Only skip our resolution when CC was set explicitly on the command line
# (tracked in .MAKEOVERRIDES) -- that is the one case the user is overriding
# toolchain selection directly.
.if empty(.MAKEOVERRIDES:MCC)
_LLVM_CC != command -v clang 2>/dev/null || \
    for _p in ${_TOOL_PREFIXES}; do \
        [ -x "$$_p/clang" ] && { echo "$$_p/clang"; break; }; \
    done
.  if !empty(_LLVM_CC)
CC  = ${_LLVM_CC}
CXX = ${_LLVM_CC:S/clang$/clang++/}
.  else
.    error "TOOLCHAIN=llvm: no clang found on PATH or this OS's known install prefixes (${_TOOL_PREFIXES}). Add clang to PATH, set TOOLCHAIN=gcc, or set CC=/path/to/clang explicitly."
.  endif
.endif

LD  ?= ${CC}
AR  ?= ar
AS  ?= as
RANLIB ?= ranlib

# ---------------------------------------------------------------------------
# Cross-compilation (REQ-toolchain-mk-must-set-explicit-cc-paths-req-v5).
#
# clang is a single binary that targets many platforms via --target/--sysroot
# -- unlike gcc, which needs a dedicated cross-built binary per target, so
# real cross support is only implemented here, not in mk.toolchain.gcc.mk.
#
# Confirmed empirically before this fix: building TARGET=freebsd from Linux
# silently produced a native Linux/host-arch ELF binary in build/freebsd-*/,
# not a FreeBSD one -- the directory name was right, the binary was not.
#
# None of the three sysroots are bundled with this project -- they're large
# and each has its own license/distribution terms (FreeBSD's base.txz is
# fully open and freely redistributable; a Linux sysroot is just files from
# a real Linux system; the macOS SDK is Apple-licensed for building on/for
# Apple platforms -- extract your own from a local Xcode install, don't
# redistribute it). See scripts/prep-*-sysroot.sh.
# ---------------------------------------------------------------------------
# Skip the sysroot requirement for a bare `-V` query or a `clean` -- neither
# actually invokes the compiler, so a missing sysroot shouldn't block them
# (found empirically: `bmake -V OS_ARCH TARGET=linux TARGET_ARCH=amd64` from
# a non-Linux host used to .error out over a sysroot it never needed).
# @impl 0f87-6a98-5de3-5c78
.if ${BMK_IS_NATIVE_BUILD} == "no" && empty(.MAKEFLAGS:M-V*) && !make(clean)
# @impl 0f87-6a98-5de3-61b8
.  if ${TARGET_ARCH} == "amd64"
_CROSS_ARCH = x86_64
.  elif ${TARGET_ARCH} == "arm64"
_CROSS_ARCH = aarch64
.  else
_CROSS_ARCH = ${TARGET_ARCH}
.  endif

#  @impl 0f87-6a98-5de3-61b8
.  if ${TARGET} == "freebsd"
.    if !defined(BMK_FREEBSD_SYSROOT) || empty(BMK_FREEBSD_SYSROOT)
.      error "Cross-compiling TARGET=freebsd requires BMK_FREEBSD_SYSROOT=/path/to/sysroot -- extract usr/include, usr/lib, lib from a FreeBSD release's base.txz (https://download.freebsd.org/ftp/releases/<arch>/<arch>/<version>-RELEASE/base.txz), no FreeBSD host needed. See scripts/prep-freebsd-sysroot.sh."
.    endif
_CROSS_FLAGS = --target=${_CROSS_ARCH}-unknown-freebsd --sysroot=${BMK_FREEBSD_SYSROOT} -fuse-ld=lld
.  elif ${TARGET} == "linux"
.    if !defined(BMK_LINUX_SYSROOT) || empty(BMK_LINUX_SYSROOT)
.      error "Cross-compiling TARGET=linux requires BMK_LINUX_SYSROOT=/path/to/sysroot -- usr/include, usr/lib/<multiarch>, lib/<multiarch> from a real Linux system (a distro rootfs is fine). See scripts/prep-linux-sysroot.sh. Note: extract it on a case-SENSITIVE filesystem -- Linux kernel headers contain names that collide on case-insensitive ones (e.g. macOS APFS default)."
.    endif
# No "unknown" vendor component here (unlike the freebsd/macos triples):
# clang locates a distro's multiarch headers (.../usr/include/<triple>/bits/...)
# by searching for a directory named exactly after the target triple, and
# glibc distros (confirmed on Debian) name that directory "<arch>-linux-gnu",
# not "<arch>-unknown-linux-gnu". Empirically found -- the sysroot silently
# built without erroring, but the compile failed with a missing-header error.
_CROSS_FLAGS = --target=${_CROSS_ARCH}-linux-gnu --sysroot=${BMK_LINUX_SYSROOT} -fuse-ld=lld
.  elif ${TARGET} == "macos"
.    if !defined(BMK_MACOS_SYSROOT) || empty(BMK_MACOS_SYSROOT)
.      error "Cross-compiling TARGET=macos requires BMK_MACOS_SYSROOT=/path/to/MacOSX.sdk -- extract your own from a local Xcode install (xcrun --show-sdk-path on a Mac). Apple's SDK license covers building on/for Apple platforms; use your own extracted copy, don't redistribute it. See scripts/prep-macos-sysroot.sh."
.    endif
# The SDK's own version doubles as the default deployment target unless the
# caller wants something older (BMK_MACOS_MIN_VERSION=).
_SDK_VERSION != sed -n 's/.*"Version":"\([0-9.]*\)".*/\1/p' ${BMK_MACOS_SYSROOT}/SDKSettings.json 2>/dev/null | head -1
_MACOS_MIN_VERSION = ${BMK_MACOS_MIN_VERSION:U${_SDK_VERSION}}
# Empirically found: Debian's clang package generates the older
# -macosx_version_min ld64 flag, but the ld64.lld it links against expects
# the newer -platform_version -- an internal driver/linker mismatch in how
# that distro packages the two separately. Passing -platform_version
# explicitly works around it regardless of whose fault the mismatch is.
_CROSS_FLAGS = --target=${_CROSS_ARCH}-apple-macos${_MACOS_MIN_VERSION} --sysroot=${BMK_MACOS_SYSROOT} \
    -fuse-ld=lld -Wl,-platform_version,macos,${_MACOS_MIN_VERSION}.0,${_SDK_VERSION}
#  @impl 0f87-6a98-5de3-a99c
.  elif ${TARGET} == "netbsd"
.    if !defined(BMK_NETBSD_SYSROOT) || empty(BMK_NETBSD_SYSROOT)
.      error "Cross-compiling TARGET=netbsd requires BMK_NETBSD_SYSROOT=/path/to/sysroot -- usr/include, usr/lib, and libexec/ld.elf_so from a real NetBSD system (a provisioned NetBSD VM is fine). See scripts/prep-netbsd-sysroot.sh."
.    endif
# NetBSD's own dynamic linker is /libexec/ld.elf_so, not /lib/ld-* like
# glibc/musl Linux -- the sysroot must have that file at that exact path
# for the produced binary's PT_INTERP to resolve at runtime.
#
# Unlike the freebsd/linux/macos triples, clang's NetBSD driver support
# (at least in the clang 14 this was found on) does not auto-add the
# sysroot's usr/lib to the linker search path from --sysroot alone --
# found empirically: ld.lld reported "unable to find library -lc" even
# though usr/lib/libc.so genuinely existed in the sysroot. -L makes it
# explicit rather than relying on that auto-injection.
_CROSS_FLAGS = --target=${_CROSS_ARCH}-unknown-netbsd --sysroot=${BMK_NETBSD_SYSROOT} \
    -fuse-ld=lld -L${BMK_NETBSD_SYSROOT}/usr/lib
# win-target-tiered-toolchain-req tier 2: mingw-w64 cross-compilation, no
# Cygwin/Windows host required (tier 1 -- TOOLCHAIN=msvc or Cygwin-native
# gcc/llvm run FROM a Cygwin host -- lives in mk.toolchain.msvc.mk and this
# same file's host-native path, not here).
# @impl 0f87-6a98-96de-785b
.  elif ${TARGET} == "win"
.    if !defined(BMK_MINGW_SYSROOT) || empty(BMK_MINGW_SYSROOT)
.      error "Cross-compiling TARGET=win (tier 2, mingw-w64) requires BMK_MINGW_SYSROOT=/path/to/mingw-w64/<triple> -- a directory containing include/ and lib/ for the target triple (e.g. an llvm-mingw or mingw-w64-gcc install's x86_64-w64-mingw32/ subdirectory). See scripts/prep-mingw-sysroot.sh. For a Cygwin-hosted native build instead (tier 1), use TOOLCHAIN=msvc or run this same TOOLCHAIN=llvm build directly from a Cygwin host (no cross flags needed there -- BMK_IS_NATIVE_BUILD=yes)."
.    endif
# mingw-w64's own dynamic loader/ABI conventions are handled by its libgcc/
# CRT startup objects bundled in the sysroot's lib/ -- no separate -L needed
# beyond --sysroot, unlike NetBSD above (confirmed against llvm-mingw's own
# documented sysroot layout; not yet verified against a real build here).
_CROSS_FLAGS = --target=${_CROSS_ARCH}-w64-mingw32 --sysroot=${BMK_MINGW_SYSROOT} -fuse-ld=lld
#  @impl 0f87-6a98-5de3-c340
.  else
.    error "Cross-compiling to TARGET=${TARGET} is not supported -- recognized cross targets are freebsd, linux, macos, netbsd, win. A silently-native build (compiling with no cross flags at all while claiming to target ${TARGET}) is worse than failing loudly here."
.  endif

.  if defined(_CROSS_FLAGS) && !empty(_CROSS_FLAGS)
CC  := ${CC} ${_CROSS_FLAGS}
CXX := ${CXX} ${_CROSS_FLAGS}
LD  = ${CC}
.  endif
.endif

.endif # _MK_TOOLCHAIN_LLVM_MK_
