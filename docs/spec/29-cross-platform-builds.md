# Bmake It — 29: Cross-Platform Builds

Status: DRAFT, synthesized from confirmed `project-model/req/` objects and the
current code (`mk/mk.common.mk`, `mk/mk.toolchain.*.mk`, `mk/mk.lib.mk`,
`mk/mk.crosstest.mk`). What is verified, and how, is in "What is verified";
what is not supported is said so in "Gaps".

The other specs each hold one piece: `40-cli-reference.md` (the variables),
`10-directory-layout.md` (the target key, Windows ABIs),
`05-setup-and-administration.md` (sysroots and where environments come from),
`25-imported-libraries.md` (imports), `28-platform-toolchain-constraints.md`
(which targets a module is built for) and `80-unit-testing.md` (running tests
on a target). This one says how they fit: from one host, which targets can be
built, with which toolchain, what each needs, and how the result is tested.

## Vocabulary

- **Host**: the machine `bmake` runs on — its OS and architecture
  (`_HOST_OS_LABEL`, `_HOST_ARCH_LABEL`: `macos`, `linux`, `freebsd`,
  `netbsd`, `win` for Cygwin; `amd64`, `arm64`).
- **Target**: what the output runs on — `TARGET=` (OS) and `TARGET_ARCH=`
  (architecture), BSD make's own cross-build names
  (`target-selection-uses-bmake-native-vars-req`). Unset: the host's.
- **Native build**: target OS and architecture equal the host's. Anything
  else is a **cross build** (`BMK_IS_NATIVE_BUILD=no`) — another OS, or the
  same OS on another architecture (`cross-compile-same-os-cross-arch-req`).
- **Toolchain**: `TOOLCHAIN=llvm` (default), `gcc` or `msvc`.
- **ABI**: only where a target OS has more than one — Linux `glibc` (default)
  or `musl`; Windows `msvc` (default), `mingw` or `cygwin`. On Windows it is
  read from the compiler, not taken on trust (`win-abi-from-compiler-req`); an
  ABI the target does not have is an error (`abi-valid-for-target-req`).
- **Target key**: `<os>-<arch>[-<toolchain>][-<abi>]`, defaults omitted —
  the name of every output directory (`build/<key>/`), so outputs for
  different targets sit side by side in one tree.

## Who can build what

Legend: **✔** verified in Bmake It's matrix (built, and run where a target
machine exists); **○** supported by the code, not verified; **✗** not
supported (an error says so); **–** does not exist.

### Host OS × target OS

Which toolchains build a target OS's output on a host OS.

| Host ↓ / Target → | macOS | Linux | FreeBSD | NetBSD | Windows |
|---|---|---|---|---|---|
| **macOS** | ✔ llvm, gcc | ○ llvm + sysroot | ○ llvm + sysroot | ○ llvm + sysroot | ○ llvm, gcc: mingw-w64 |
| **Linux** | ✗ llvm + SDK: compiles, does not link (Debian 13's lld and the SDK stubs) | ✔ llvm, gcc; ✔ llvm to the other architecture | ✔ llvm + sysroot (arm64; amd64 builds, no guest to run on an arm64 host) | ✔ llvm + sysroot (arm64; amd64 likewise) | ○ llvm, gcc: mingw-w64 |
| **FreeBSD** | ○ llvm + SDK | ○ llvm + sysroot | ✔ llvm, gcc | ○ llvm + sysroot | ○ llvm, gcc: mingw-w64 |
| **NetBSD** | ○ llvm + SDK | ○ llvm + sysroot | ○ llvm + sysroot | ✔ llvm, gcc | ○ llvm, gcc: mingw-w64 |
| **Windows (Cygwin)** | ○ llvm + SDK | ○ llvm + sysroot | ○ llvm + sysroot | ○ llvm + sysroot | ✔ llvm, gcc (Cygwin and mingw-w64), msvc |

"+ sysroot"/"+ SDK": `BMK_<OS>_SYSROOT` (below). Every ○ goes through the
same clang `--target`/`--sysroot` path as the ✔ cells; it is ○ because no
matrix cell builds on that host for that target, not because something is
known to be missing.

### Toolchain × target ABI

Per output runtime, natively (on that OS) and as a cross build.

| Toolchain ↓ / ABI → | Linux glibc | Linux musl | macOS | FreeBSD | NetBSD | Windows Cygwin | Windows mingw-w64 | Windows MSVC |
|---|---|---|---|---|---|---|---|---|
| **llvm** | native ✔, cross ✔ | native ✔, cross ✗ | native ✔, cross ✗ from Linux (does not link), ○ elsewhere | native ✔, cross ✔ | native ✔, cross ✔ | native ✔ | on Cygwin ✔ (`ABI=mingw`), cross ○ | ✗ — by hand ○, toolchain planned |
| **gcc** | native ✔, cross ✗ (planned) | native ✔, cross ✗ (planned) | native ✔, cross ✗ (not possible) | native ✔, cross ✗ (planned) | native ✔, cross ✗ (planned) | native ✔ | on Cygwin ✔ (`ABI=mingw`), cross ○ (`<triple>-gcc`) | ✗ |
| **msvc** | – | – | – | – | – | – | – | native ✔ (Cygwin host; EWDK or Visual Studio) |

"Native" Linux musl is verified in musl containers. "Cross ✗" for gcc: only
mingw-w64's gcc is looked for today; the others are planned (see "Gaps"),
except macOS, which gcc cannot target. Windows Cygwin output exists only natively —
it needs Cygwin's own compilers.

### Per toolchain

| Toolchain | Native | Cross |
|---|---|---|
| `llvm` | every host | any host to `linux`, `freebsd`, `netbsd`, `macos` with that target's sysroot; to `win` as mingw-w64 output |
| `gcc` | every host | today only to `win`, as mingw-w64 output, with `<triple>-gcc`; other targets planned (`gcc-cross-toolchain-req`) |
| `msvc` | Windows (Cygwin host), `win` of the host's architecture | none: MSVC only targets Windows from Windows; asking is an error naming `TOOLCHAIN=llvm` as the cross path |

clang is one binary for every target (`--target=`), which is why cross
support lives in `mk.toolchain.llvm.mk` (`cross-compile-via-clang-target-
sysroot-dec`). A target OS with no recipe is an error, never a silently native
build (`cross-target-selection-must-fail-loudly-req`): building `TARGET=freebsd`
from Linux once produced a Linux binary in `build/freebsd-*/`.

### Windows output

A Windows host is a Cygwin host. From it, `TARGET=win` has three runtimes:

| Output | How | Key |
|---|---|---|
| Cygwin (POSIX, `cygwin1.dll`) | `TOOLCHAIN=llvm` or `gcc` | `win-amd64-cygwin`, `-gcc-cygwin` |
| mingw-w64 (native, no Cygwin) | `ABI=mingw` with `llvm` or `gcc` (`mingw-on-cygwin-req`) | `win-amd64-mingw`, `-gcc-mingw` |
| MSVC (native) | `TOOLCHAIN=msvc`: `cl.exe`/`link.exe`, found through Visual Studio or a mounted EWDK (`BMK_EWDK_ROOT=`, `msvc-ewdk-root-req`) | `win-amd64` |

From any other host, Windows output is mingw-w64 only
(`win-target-via-cross-toolchain-req`, `win-target-tiered-toolchain-req`):
clang with `--target=<arch>-w64-mingw32`, using an installed
`<triple>-gcc`'s headers, CRT and libgcc, or an llvm-mingw tree given as
`BMK_MINGW_SYSROOT=` (the only way for `arm64`). Clang without that sysroot
links winpthread and uses emulated TLS to match the installed gcc's libstdc++
(`mingw-clang-links-winpthread-req`, `mingw-clang-emulated-tls-req`).

## What a cross build needs

**A sysroot of the target** for `llvm`: the target's headers, libraries,
startup files and dynamic linker, so the compiler never uses the host's. One
variable per target OS — `BMK_LINUX_SYSROOT`, `BMK_FREEBSD_SYSROOT`,
`BMK_NETBSD_SYSROOT`, `BMK_MACOS_SYSROOT` (an `MacOSX.sdk`) — set in a hook
file or on the command line. The build adds `--target=<triple>
--sysroot=<dir> -fuse-ld=lld`. A missing one stops the build saying what
the sysroot must hold and which script makes one
(`tests/harness/fetch/build-sysroot-<os>.sh`); a `-V` query or `clean`,
which compile nothing, never ask for it
(`cross-compile-check-scoped-to-actual-builds-req`). What each sysroot
contains, and why a Linux one must be extracted on a case-sensitive
filesystem: `05-setup-and-administration.md`. Nothing provisions sysroots
for a project yet; that is specified there (the configuration makefile).

Per-target details the toolchain file takes care of
(`cross-compile-per-target-triple-quirks-req`):

- **Linux**: triple `<arch>-linux-gnu` (no vendor field: clang finds
  Debian's multiarch headers by that exact name).
- **macOS**: deployment target = the SDK's version unless
  `BMK_MACOS_MIN_VERSION=` is older; the platform version is passed to
  `ld64.lld` explicitly.
- **NetBSD**: `-L<sysroot>/usr/lib`, and two load segments without RELRO —
  NetBSD's loader rejects lld's default layout
  (`netbsd-cross-binaries-run-req`).
- **The same OS on another architecture** (Linux arm64 → amd64) is a cross
  build like any other: it needs that architecture's sysroot.

**Dependencies are looked up in the target's world, not the host's.**

- `IMPORT=pkg:` and `REQUIRES=` ask pkg-config inside the sysroot only:
  `PKG_CONFIG_SYSROOT_DIR` and the target OS's own `.pc` directories
  (Debian multiarch, FreeBSD `libdata`, NetBSD `pkg` and `X11R7`), never the
  host's (`cross-import-from-sysroot-req`, `cross-requires-from-sysroot-req`,
  `pkg-config-sysroot-only-inside-req`). A host `.pc` file once leaked
  aarch64 flags into an amd64 build (`cross-import-host-pc-obs`).
- mingw-w64 output uses `<triple>-pkg-config`, or `BMK_MINGW_SYSROOT`'s
  `lib/pkgconfig` (`pkg-config-matches-output-abi-req`).
- An OS-only sysroot has no third-party libraries: a dependency must be put
  into the sysroot first (`cross-sysroot-os-only-obs`). Assembling a sysroot
  with prerequisites is a candidate, not specified
  (`cross-sysroot-with-prerequisites-cand`).
- `IMPORT=fetch:` builds the upstream sources with the same `CC`/`CXX`, so a
  cross build carries `--target`/`--sysroot`; with `FETCH_BUILD=autotools`
  `--host=<triple>` is passed too. **CMake and Meson builds lose the cross
  flags** (they want a bare compiler path): see "Gaps".

## Running and testing what was built

- **`bmake test`** for a target the host cannot run needs a runner:
  `TEST_RUNNER.<os>-<arch>=ssh:…|docker:…|cmd:…` (or `TEST_RUNNER=`). The
  tests are staged with the libraries they load, run by Kyua on the target,
  and the reports come back (`cross-test-runner-req`,
  `cross-test-ships-dependencies-req`). With no runner it stops before
  building, naming the variables to set (`cross-test-needs-runner-req`).
  `TEST_RUNNER=local` runs a foreign Linux target here through qemu-user
  with the sysroot as `QEMU_LD_PREFIX` (`cross-test-local-emulated-req`).
  See `80-unit-testing.md`, "Cross targets".
- **Native Windows runtimes** (MSVC, mingw-w64) are tested on the Cygwin
  host itself: the Cygwin Kyua runs their test programs, which link the ATF
  Bmake It builds for them (`native-windows-tests-req`). `bmake test` for a
  cross build to Windows stops saying so.
- **`bmake run`** starts a program on the build host only. Running a foreign
  target's program in a guest is specified, not implemented
  (`run-in-guest-desktop-req`).

## What is verified

Bmake It's own matrix (`tests/README.md`, `tests/harness`):

- **Native suites** on macOS, Linux (glibc and musl, amd64 and arm64, in
  containers and guests), FreeBSD and NetBSD (QEMU guests and real hosts),
  and on a Windows host for Cygwin, mingw-w64 and MSVC output.
- **Cross cells**: Hello is built on one platform and **run on the target**:
  Linux arm64 ↔ Linux amd64, Linux → FreeBSD arm64, Linux → NetBSD arm64
  (`harness-tests-full-cross-build-matrix-req`). FreeBSD and NetBSD amd64 build
  but have no guest to run on, on an arm64 host.
- **pkg-config in a cross build** reads only the sysroot (case 100).

## Gaps

Not supported today; each is a decision to make, not a silent behaviour:

- **gcc cross-compilers** other than mingw-w64's are not looked for yet —
  deferred, to be supported (`gcc-cross-toolchain-req`). gcc can
  cross-compile, but each target needs its own gcc and binutils, built for
  it: `TOOLCHAIN=gcc` will look for `<triple>-gcc`/`-g++`/`-ar` (or a
  `BMK_GCC_CROSS_PREFIX=` override), pass the target's sysroot, and name the
  compiler it looked for when there is none. Linux targets first (Debian and
  Ubuntu package `gcc-<arch>-linux-gnu`); FreeBSD and NetBSD need a
  user-built cross gcc (crosstool-ng); macOS cannot be targeted with gcc,
  which has no Mach-O linker of its own.
- **musl as a cross target**: `ABI=musl` labels native musl output (built in a
  musl container); a cross build always uses the `-linux-gnu` triple.
- **`IMPORT=fetch:` with CMake or Meson** in a cross build: the cross flags are
  lost; a toolchain-file/cross-file generator is deferred
  (`26-fetched-external-sources.md`).
- **Linux → macOS** builds but does not link from the Debian 13 container (its
  lld cannot read the SDK's stubs).
- **Windows from a non-Windows host** is mingw-w64 only and not in the
  matrix: there is no Windows guest, and no Windows sysroot recipe.
- **clang for MSVC output** (`--target=<arch>-pc-windows-msvc` with
  `lld-link` and MSVC's headers and libraries) works by hand on the Windows
  host; it is not a toolchain yet. The ABI detection already labels such a
  compiler's output `msvc`.
- **Sysroot provisioning** for projects (fetch, build, keep, share) is
  specified in `05-setup-and-administration.md`, not implemented; the harness
  scripts make sysroots for Bmake It's own tests.
- **macOS and Windows guests** cannot be built unattended (licensing, Apple
  hardware), so those targets are verified natively only.
