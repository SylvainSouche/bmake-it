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
# @impl 0f87-6aa9-39c9-34a5 -- _TOOL_PREFIXES is checked BEFORE ambient
# $PATH (command -v), not after: each mk.paths.<os>.mk already lists that
# OS's own correct priority order, but relying on command -v first makes
# the result depend on the INVOKING SHELL's PATH instead, which Bmake It
# doesn't control -- found on macOS specifically, where /usr/bin (Apple's
# Xcode toolchain) and /opt/local/bin (MacPorts, the actual intended
# default per CON-cross-platform-targets) can appear in either order
# depending on who set up that shell's profile. command -v is now only a
# last-resort fallback, for a genuinely nonstandard install location none
# of the known prefixes cover.
#
# Bare `!defined(CC)` is not a safe guard here: bmake's own sys.mk
# unconditionally soft-assigns `CC?=cc` before any of our files are parsed
# (confirmed on real NetBSD -- /usr/share/mk/sys.mk:28), so CC is *always*
# already "defined" by the time this file runs, regardless of TOOLCHAIN=.
# Only skip our resolution when CC was set explicitly on the command line
# (tracked in .MAKEOVERRIDES) -- that is the one case the user is overriding
# toolchain selection directly.
.if empty(.MAKEOVERRIDES:MCC)
_LLVM_CC != _found=""; \
    for _p in ${_TOOL_PREFIXES}; do \
        if [ -x "$$_p/clang" ]; then _found="$$_p/clang"; break; fi; \
    done; \
    if [ -n "$$_found" ]; then echo "$$_found"; else command -v clang 2>/dev/null || true; fi
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
# real cross support is only implemented here, not in mk.toolchain.gcc.mk
# (except mingw-w64, whose gcc builds are commonly packaged: see there).
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
# redistribute it). See tests/harness/fetch/build-sysroot-*.sh.
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
.      error "Cross-compiling TARGET=freebsd requires BMK_FREEBSD_SYSROOT=/path/to/sysroot -- extract usr/include, usr/lib, lib from a FreeBSD release's base.txz (https://download.freebsd.org/ftp/releases/<arch>/<arch>/<version>-RELEASE/base.txz), no FreeBSD host needed. tests/harness/fetch/build-sysroot-freebsd.sh in the Bmake It tree makes one, as a tar to extract."
.    endif
_CROSS_FLAGS = --target=${_CROSS_ARCH}-unknown-freebsd --sysroot=${BMK_FREEBSD_SYSROOT} -fuse-ld=lld
.  elif ${TARGET} == "linux"
.    if !defined(BMK_LINUX_SYSROOT) || empty(BMK_LINUX_SYSROOT)
.      error "Cross-compiling TARGET=linux requires BMK_LINUX_SYSROOT=/path/to/sysroot -- usr/include, usr/lib/<multiarch>, lib/<multiarch> from a real Linux system (a distro rootfs is fine). tests/harness/fetch/build-sysroot-linux.sh in the Bmake It tree makes one, as a tar to extract. Note: extract it on a case-SENSITIVE filesystem -- Linux kernel headers contain names that collide on case-insensitive ones (e.g. macOS APFS default)."
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
.      error "Cross-compiling TARGET=macos requires BMK_MACOS_SYSROOT=/path/to/MacOSX.sdk -- extract your own from a local Xcode install (xcrun --show-sdk-path on a Mac). Apple's SDK license covers building on/for Apple platforms; use your own extracted copy, don't redistribute it. tests/harness/fetch/build-sysroot-macos.sh in the Bmake It tree makes one, as a tar to extract."
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
.      error "Cross-compiling TARGET=netbsd requires BMK_NETBSD_SYSROOT=/path/to/sysroot -- usr/include, usr/lib, and libexec/ld.elf_so from a real NetBSD system (a provisioned NetBSD VM is fine). tests/harness/fetch/build-sysroot-netbsd.sh in the Bmake It tree makes one, as a tar to extract."
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
# NetBSD's ld.elf_so maps at most two PT_LOAD segments and does not take a
# GNU_RELRO one, but lld by default splits code from read-only data
# (-z separate-code: four PT_LOAD) and adds RELRO. A shared library so linked
# is rejected at run time with only "Shared object ... not found" (found by
# running the cross-built Hello on a real NetBSD 10.2 guest). Native NetBSD
# libraries have two segments; ask lld for the same.
# @impl 0f87-6ad7-1f32-4d7a
_CROSS_FLAGS = --target=${_CROSS_ARCH}-unknown-netbsd --sysroot=${BMK_NETBSD_SYSROOT} \
    -fuse-ld=lld -L${BMK_NETBSD_SYSROOT}/usr/lib -Wl,-z,noseparate-code -Wl,--no-rosegment -Wl,-z,norelro
# TARGET=win: mingw-w64 (tier 2 and ABI=mingw on Cygwin) is set up below,
# outside this -V/clean-skipped block -- see there.
.  elif ${TARGET} == "win"
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

# ---------------------------------------------------------------------------
# mingw-w64 output (win-target-tiered-toolchain-req tier 2: cross-compiling
# to win from any host; mingw-on-cygwin-req: ABI=mingw on a Cygwin host for
# its own arch -- without it, clang there makes Cygwin output).
#
# --target is set even for a -V query or clean (only the checks are
# skipped): mk.common.mk asks this CC for -dumpmachine to label the build,
# and plain clang would answer with the host's own triple.
#
# --sysroot only when BMK_MINGW_SYSROOT is given. Otherwise clang finds an
# installed mingw-w64 gcc (<triple>-gcc on PATH) and uses its headers, CRT
# and libgcc itself -- found on Cygwin with mingw64-x86_64-gcc-g++: an
# explicit --sysroot=/usr/x86_64-w64-mingw32/sys-root/mingw compiled C but
# lost the C++ headers and libgcc, which live outside it under
# /usr/lib/gcc/x86_64-w64-mingw32/<ver>; without --sysroot C and C++ both
# build and link. Linker: lld if installed, else mingw's own GNU ld (bfd),
# put in LDFLAGS, not CC, so compiles don't warn about an unused flag.
# @impl 0f87-6a98-96de-785b
# @impl 7854-6ad0-e970-479a
# ---------------------------------------------------------------------------
.if ${_BMK_WIN_MINGW:Uno} == "yes"
_MINGW_GCC != command -v ${_MINGW_TRIPLE}-gcc 2>/dev/null || true
_MINGW_LLD != command -v ld.lld 2>/dev/null || true
_MINGW_BFD != command -v ${_MINGW_TRIPLE}-ld 2>/dev/null || true
# mingw-sysroot-error-actionable-req-v2: name what is missing and where it
# comes from -- this error once sent users to a scripts/prep-mingw-
# sysroot.sh that never existed (2026-10-15).
# @impl 7854-6ad0-e744-0614
_MINGW_HELP = clang needs, for ${_MINGW_TRIPLE}: headers, CRT and import libraries, either from an installed mingw-w64 gcc (${_MINGW_TRIPLE}-gcc on PATH, found automatically) or from BMK_MINGW_SYSROOT=<dir with include/ and lib/>; and a linker, ld.lld or ${_MINGW_TRIPLE}-ld. Sources: on Cygwin, mingw64-x86_64-gcc-core and mingw64-x86_64-gcc-g++ (x86_64 only; they bring x86_64-w64-mingw32-ld) and optionally lld; on Debian/Ubuntu, mingw-w64; for aarch64, an llvm-mingw release, whose <install>/${_MINGW_TRIPLE} is a BMK_MINGW_SYSROOT. On a Cygwin host, TOOLCHAIN=msvc gives MSVC output, and llvm or gcc without ABI=mingw give Cygwin (cygwin1.dll) output.
.  if empty(.MAKEFLAGS:M-V*) && !make(clean)
.    if !empty(BMK_MINGW_SYSROOT) && (!exists(${BMK_MINGW_SYSROOT}/include) || !exists(${BMK_MINGW_SYSROOT}/lib))
.      error "BMK_MINGW_SYSROOT=${BMK_MINGW_SYSROOT} is not a mingw-w64 sysroot for ${_MINGW_TRIPLE}: it has no include/ or no lib/ directory. ${_MINGW_HELP}"
.    elif empty(BMK_MINGW_SYSROOT) && empty(_MINGW_GCC)
.      error "TARGET=win-${TARGET_ARCH} with TOOLCHAIN=llvm is a mingw-w64 build, and there is no mingw-w64 for ${_MINGW_TRIPLE} here: no BMK_MINGW_SYSROOT, and no ${_MINGW_TRIPLE}-gcc on PATH to take one from. ${_MINGW_HELP}"
.    elif empty(_MINGW_LLD) && empty(_MINGW_BFD)
.      error "TARGET=win-${TARGET_ARCH} with TOOLCHAIN=llvm is a mingw-w64 build and has no linker for ${_MINGW_TRIPLE}: neither ld.lld nor ${_MINGW_TRIPLE}-ld is on PATH. ${_MINGW_HELP}"
.    endif
.  endif
_MINGW_FLAGS = --target=${_MINGW_TRIPLE}
.  if !empty(BMK_MINGW_SYSROOT)
_MINGW_FLAGS += --sysroot=${BMK_MINGW_SYSROOT}
.  endif
CC  := ${CC} ${_MINGW_FLAGS}
CXX := ${CXX} ${_MINGW_FLAGS}
LD  = ${CC}
.  if !empty(_MINGW_LLD)
LDFLAGS += -fuse-ld=lld
.  else
LDFLAGS += -fuse-ld=bfd
.  endif
# mingw-clang-links-winpthread-req: mingw-w64 gcc links winpthread on every
# link (its specs: %{!no-pthread:-lpthread}); clang's mingw driver does not,
# so pthread_create (C) and std::mutex/std::thread (C++, libstdc++ built on
# winpthread) were undefined with clang (2026-10-15). -pthread makes clang
# add -lpthread the same way.
# @impl 7854-6ad0-fb85-07d4
LDFLAGS += -pthread
# mingw-clang-emulated-tls-req: without BMK_MINGW_SYSROOT, clang links the
# libstdc++ of the installed mingw-w64 gcc, which gcc builds with emulated
# TLS: its thread-locals exist only as __emutls_v.<name> (e.g. std::
# call_once's __once_callable/__once_call). clang emits native TLS by
# default, and std::call_once failed to link (OpenRider, 2026-10-15).
# -femulated-tls matches it. An llvm-mingw sysroot's own C++ library uses
# native TLS, so a build given BMK_MINGW_SYSROOT does not get it. The flag
# is part of every object's compile command, so objects built before it
# are rebuilt by the inputs hash on the next build.
# @impl 7854-6ad1-4114-22d7
.  if empty(BMK_MINGW_SYSROOT)
CFLAGS   += -femulated-tls
CXXFLAGS += -femulated-tls
LDFLAGS  += -femulated-tls
.  endif
.endif

.endif # _MK_TOOLCHAIN_LLVM_MK_
