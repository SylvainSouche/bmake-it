# Bmake It unit tests

## Cross-platform verification (2026-08-31)

All 27 cases pass on every platform family CON-cross-platform-targets
requires, run for real rather than assumed from the macOS results:

| Platform | How | Toolchain |
|---|---|---|
| macOS (MacPorts) | native | `/opt/local/bin/bmake` |
| Linux (Debian bookworm) | Colima/Docker VM | `pkg install bmake gcc` |
| NetBSD 10.1 (arm64) | QEMU VM (`hvf` accel) | native `/usr/bin/make` + base clang, nothing installed |

Running on real Linux and a real BSD (not just macOS) is what surfaced two
bugs invisible on macOS alone: a self-reentrant nested-`bmake` invocation
(`gen-mod-order.sh`/`gen-fw-order.sh`, now fixed with absolute-path
resolution and atomic cache writes) and archives silently corrupted by
macOS AppleDouble sidecar files (`pack-cases.sh` now strips them). Both are
model requirements now (`nested-invocation-reentrancy-guard-req`), not just
patches.

## The cross-platform matrix (tests/harness)

The unit suite above runs on whatever host you are on. The *matrix* runs it
(and a cross-built program) on every platform we can: Linux in containers,
FreeBSD and NetBSD as real QEMU guests, macOS natively. It is plain shell and
make and is not part of the product.

```sh
cd tests/harness
export BMK_CACHE=/path/to/cache        # default ~/.bmk-cache; may be an external drive
sh vm.sh status                        # what exists for each VM platform
sh matrix.sh list                      # every cell: build host x target x toolchain
sh matrix.sh run 'native-freebsd_arm64-*'
sh matrix.sh run cross-linux_arm64-freebsd-arm64   # build on Linux, RUN on FreeBSD
sh matrix.sh report                    # the grid: build and run result per cell
make fetch provision build test report # all of it
```

- **This machine as a cell**: `windows_amd64` (Cygwin), `freebsd_host` and
  `netbsd_host` are `KIND host` platforms: their native cells run the suite
  right on the machine running `matrix.sh` (with the base system's
  `/usr/bin/make` on the BSDs), and are *blocked*, with the reason, on any
  other host. On a FreeBSD machine: `pkg install pkgconf gcc cmake-core
  doxygen atf` (clang, make and kyua are in the base system), then
  `sh matrix.sh run 'native-freebsd_host-*'`.
- **Cells** are in `matrix.tsv`. A *native* cell runs the whole suite inside the
  platform; a *cross* cell builds Hello for the target and then executes it
  there. A cell that cannot run is listed with its reason (an amd64 BSD guest
  stalls under software emulation on an arm64 host; a macOS guest needs Apple
  hardware; there is no Windows guest yet), never silently dropped.
- **VMs** (`vm.sh`): the published image is kept as downloaded, decompressed
  once into a read-only *base*, provisioned once into a *layer* (ssh key,
  sshd, the packages the suite needs), and each run boots a throw-away
  *overlay* on the layer: `vm.sh reset <id>` restores the provisioned state
  by deleting it. On a host of the same architecture the guest is
  hardware-accelerated (FreeBSD 15.1 arm64 reaches ssh in under a minute on
  an M-series Mac).
- **Where things live**: `BMK_CACHE` holds images, bases, layers, overlays,
  sysroots, keys, logs and results (`BMK_VMS` moves just the throw-away
  overlays to a faster disk if the cache sits on a slow external drive); `BMK_RUN` (default under `$TMPDIR`) holds
  sockets and pidfiles, which an exFAT drive cannot hold. A container runtime
  such as Colima shares `$HOME` but usually not an external drive, so the
  scripts stage what a container reads under `$HOME` first.
- **Sysroots** for the BSDs are taken from the guest itself
  (`vm.sh sysroot freebsd_arm64`), so a cross-built binary matches the OS it
  runs on; Linux sysroots come from `fetch/build-sysroot-linux.sh`.
- The container images are tagged `bmk/*`. If you already have the earlier
  `rade-bmake/*` tags: `docker tag rade-bmake/linux-glibc:arm64 bmk/linux-glibc:arm64`
  (and likewise for the other two) instead of rebuilding.

### Results (2026-10-30, Windows 10 amd64 host)

104 cases, with the ATF Bmake It carries (case 104, cases 43/86/91/92/99
now run on MSVC and mingw output too).

| Cell | llvm | gcc |
|---|---|---|
| Debian 13 amd64 (QEMU, WHPX) | 100 pass, 4 skip | 103 pass, 1 skip |
| FreeBSD 15.1 amd64 (QEMU, WHPX) | 103 pass, 1 skip | 100 pass, 4 skip |
| NetBSD 11.0 amd64 (QEMU, WHPX) | 100 pass, 4 skip | 102 pass, 2 skip |
| Windows, Cygwin output (host) | 96 pass, 8 skip | 96 pass, 8 skip |

No failures. The MSVC and mingw cells did not complete: the external drive
holding the cache (and the EWDK image the MSVC cell mounts) failed during
the run (I/O retries, then it dropped off USB). The ATF cases (43, 86, 91,
92, 99, 102, 103, 104) passed for both outputs when run on their own the
same day; the full cells are to be rerun. atf-bmk's own self-test
(`scripts/atf-selftest.sh`, `docs/spec/81-atf-feature-matrix.md`): posix
334 results, win (mingw) 194, no regressions; MSVC not run, for the same
reason.

### Results (2026-10-29, Windows 10 amd64 host)

103 cases. Guests are amd64 QEMU VMs under WHPX (UEFI boot, packages from
the offline cache); the host cells run the suite right on Windows.

| Cell | llvm | gcc |
|---|---|---|
| Debian 13 amd64 (QEMU, WHPX) | 99 pass, 4 skip | 102 pass, 1 skip |
| FreeBSD 15.1 amd64 (QEMU, WHPX) | 102 pass, 1 skip | 99 pass, 4 skip |
| NetBSD 11.0 amd64 (QEMU, WHPX) | 99 pass, 4 skip | 101 pass, 2 skip |
| Windows, Cygwin output (host) | 95 pass, 8 skip | 95 pass, 8 skip |

| Cell | result |
|---|---|
| Windows, MSVC (EWDK, host) | 91 pass, 12 skip |
| Windows, mingw (`llvm+mingw`, host) | 91 pass, 12 skip |

No failures. Most of the Windows skips are cases with no meaning for a
native Windows runtime (`bmake test` with ATF, POSIX shared-library
chains). The first MSVC and mingw runs failed cases 102 and 103 on the
tests themselves: mingw programs print CRLF, and the no-pkg-config PATH
kept `x86_64-w64-mingw32-pkg-config` (both fixed the same day).

The first guest run of the day found a regression that Cygwin and the BSDs
hid: the prerequisite preflight asked for a downloader even for a `file://`
fetch. Case 98 hides curl and wget, and Debian has no `fetch` or `ftp` to
fall back on, so it failed only there (fixed the same day).

### Results (2026-10-20, Apple-silicon host)

| Cell | llvm | gcc |
|---|---|---|
| macOS, host | 95 pass | |
| macOS guest (tart) | 93 pass, 2 skip | 92 pass, 3 skip |
| Linux glibc arm64 (container) | 91 pass, 4 skip | 94 pass, 1 skip |
| Linux glibc amd64 (container, emulated) | 91 pass, 4 skip | 93 pass, 2 skip |
| Linux musl amd64 (container, emulated) | 91 pass, 4 skip | 93 pass, 2 skip |
| FreeBSD 15.1 arm64 (QEMU, hvf) | 94 pass, 1 skip | 91 pass, 4 skip |
| NetBSD 10.2 arm64 (QEMU, hvf) | 91 pass, 4 skip | 93 pass, 2 skip |

No failures. Skips are cases whose tool or capability is absent on that
platform (OpenMP, ASan that cannot start, macOS-only dylib chains).
Emulated platforms retry a failing case once and report one that passes only
on the retry as `flaky=N`; the amd64 gcc run had five such first attempts.

Cross cells, each built and then **run on the target** where a target exists
here: Linux arm64 to Linux amd64, Linux amd64 to Linux arm64, Linux to FreeBSD
arm64 and Linux to NetBSD arm64 all print `Hello, Bmake It!`. FreeBSD and NetBSD
amd64 build but cannot run here (blocked, reported). Linux to macOS builds but
does not link from the Debian 13 container (its lld cannot read this Mac's SDK
stubs); Windows has no guest or sysroot recipe yet. `sh matrix.sh report` prints
all of it.

Running there found defects macOS and Debian hide: fetch needed curl or wget
(bare FreeBSD has only `fetch`); `bmake test` stopped at the first failing
module under a make that runs recipes with `sh -e`; an empty variable left a
double space in an error text; a ports gcc's C++ binaries would not start;
the import cache used the `:mtime` modifier that bmake 20200710 (Debian,
Ubuntu) and NetBSD's make lack; and a shared library cross-built for NetBSD
was rejected by its loader (two load segments, no RELRO). See
`freebsd-base-run-findings-obs`, `mtime-modifier-missing-on-old-make-obs` and
`netbsd-cross-binaries-run-req`.

A guest needs RAM: the matrix runs one at a time (`MATRIX_KEEP_VMS=1` keeps
them up). On a 16 GB Mac with the container VM running, expect swap use; stop
the container VM (`colima stop`) while running the BSD and macOS cells.

## Design

- **Orchestration is pure shell** (`harness/run-tests.sh`), not make — so there
  is no nested-make contamination of `MAKEFLAGS` / `MAKELEVEL`.
- **Each test is an independent archive** under `archives/*.tar.gz`.
  The runner extracts it into a private work directory, runs `run.sh`,
  then deletes the work directory (unless `KEEP_FAILED=1`).
- **Isolated bmake**: every invocation goes through a wrapper that clears
  `MAKEFLAGS`/`MAKELEVEL`/`MFLAGS` and sets `MAKESYSPATH` + `BMK_MKDIR`.
- **Target-neutral cases** (`harness-cases-target-neutral-req`): a case never
  hardcodes Unix names. It sources `. "$BMK_TESTLIB"`
  (`harness/testlib.sh`, exported by the runner) and asks it:
  `prog_name app` (`app.exe` on Windows), `find_prog <dir> app`,
  `static_lib x` (`libx.a` / `x.lib`), `shared_lib x [major]`
  (`libx.so.3` / `libx.3.dylib` / `x.dll`), `make_shared_lib <dir> x <cc
  args>` for a fake library (a DLL plus `libx.dll.a` on Windows; `x.dll`
  plus `x.lib` under `TOOLCHAIN=msvc`), `fake_ar <dir>/libx.a <objs>` for a
  fake static one (`x.lib` from `lib.exe` under `TOOLCHAIN=msvc`),
  `with_libdir <dirs> <cmd>` (prepends to `LD_LIBRARY_PATH`,
  `DYLD_LIBRARY_PATH` or `PATH`), `prog_libdir <program>` (Windows has no
  rpath), and `need_tool <tool> [why]`, which skips the case (exit 77)
  when a tool is missing. Cases compile their fake libraries with `"$CC"`,
  which testlib sets to the toolchain under test: the mingw compiler under
  `ABI=mingw`, Bmake It's own `cl.exe` wrapper (environment included, asked
  from bmake) under `TOOLCHAIN=msvc`. `atf_pc` asks pkg-config for ATF the
  way Bmake It does (also beside the `kyua` on `PATH`), and
  `native_win_runtime` is true for mingw-w64 and MSVC output, whose ATF
  Bmake It builds itself (nothing installed to probe for). Cases run with `LC_ALL=C`, so tool
  messages can be grepped. Before these, 45 of the 100 cases failed on Cygwin for those
  reasons alone (2026-10-26).

## Running

```sh
# from the Bmake It tree
sh tests/harness/run-tests.sh           # all tests
sh tests/harness/run-tests.sh 10-       # filter by substring
KEEP_FAILED=1 sh tests/harness/run-tests.sh   # keep failing work dirs
```

On MacPorts, `bmake` is not at `/usr/bin/bmake` (the harness's default) —
set `BMAKE` as well as `BMK_SYS_MK`:

```sh
export BMK_SYS_MK=/opt/local/share/mk
export BMAKE=/opt/local/bin/bmake
sh tests/harness/run-tests.sh
```

## Regenerating archives from cases/

```sh
sh tests/harness/pack-cases.sh
```

Caution: an archive can hold **empty directories** a case relies on (e.g.
`fake/pkgroot/lib/`), and `tests/cases/` cannot, because git does not
track empty directories. To repack an edited case without losing them,
extract its current archive, copy `tests/cases/<case>/.` over it, and tar
that (how the 2026-10-26 Cygwin changes were repacked).

## Case index (spec + implementation risk)

| ID | Focus |
|----|--------|
| 01 | Framework discovery via `PREREQS=` signal; ignore `build/`/`distrib/` |
| 02 | `PREREQS` mandatory even when empty |
| 03 | Module discovery `*.m` only |
| 04 | Module topological order from `LIBS=` |
| 05 | Framework topological order from `PREREQS=` |
| 06 | Cycle detection in module order |
| 07 | `PROG`/`LIB` default to module directory name |
| 08 | `LIB_SHARED=NO` → static only |
| 09 | Versioned shared library name (`SHLIB_MAJOR`) |
| 10 | Full prog + shared-lib link end-to-end |
| 11 | Three-level headers + prereq public headers |
| 12 | `LIBS=` is link-only (private headers not exposed) |
| 13 | Target key / `OS_ARCH` / `TOOLCHAIN` suffix |
| 14 | `clean` scope does not wipe other target keys |
| 15 | External `LIBS` entries ignored by topo sort |
| 16 | `src/` auto-discovery |
| 17 | `install DESTDIR= PREFIX=` |
| 18 | `PARENT_WS` absolute path |
| 19 | `SUBDIR` isolation (workspace must not leak into modules) |
| 20 | Empty workspace builds |
| 21 | Native `CFLAGS+=` append |
| 22 | Empty `SRCS` border behaviour |
| 23 | Linux target-key ABI suffix (`glibc` omitted, `musl` shown) |
| 24 | `bmake help` at workspace/framework/module level |
| 25 | `add-parent` appends `PARENT_WS=`; usage error without `WS=` |
| 26 | `install` refuses on an unbuilt workspace |
| 27 | Workspace-root `share/` is not overlay-copied into build output |
| 28 | `PREREQS=` naming a framework that only exists in a `PARENT_WS` workspace: header+lib resolve there, binary actually runs |
| 29 | `PREREQS=` framework present in both the current workspace and a `PARENT_WS`: the local one wins for compile, link, and run |
| 30 | `add-prereq` appends `PREREQS=`, preserves order across repeated calls; usage error without `FW=` |
| 31 | `run` resolves and executes `PROGRAM=` with the right dynamic-library search path, from the workspace root, a framework dir, or a module dir; `ARGS=` passthrough; usage/not-built error paths |
| 32 | `add-prereq FW=Lib` on a sibling framework in the *same* workspace actually enables header visibility + link + run, not just the `PREREQS=` text edit |
| 33 | `add-prereq FW=Lib` where `Lib` only exists in a `PARENT_WS` workspace — same real build+link+run guarantee as 28, established via `add-prereq` instead of hand-written `PREREQS=` |
| 34 | `add-prereq FW=Lib` where `Lib` exists in both the current and a `PARENT_WS` workspace — local must still win, established via `add-prereq` |
| 35 | Linking a module before its `LIBS=` dependency is built fails with an explicit "prerequisite library X has not been built yet" diagnostic (not an opaque linker error); the same module links and runs normally once the dependency is actually built |
| 36 | Two frameworks independently producing a same-named `share/` artifact at workspace-level copy-up: byte-identical content copies silently, differing content warns but still overwrites (build succeeds, last-copied-wins) |
| 37 | The `share/common → share/<os> → share/<os>_<arch>` overlay cascade across every layer-presence combination: a file unique to any one layer survives; where two-plus layers define the same file, the most specific present layer wins |
| 38 | A framework present in both the current workspace and a `PARENT_WS`, where only the *parent's* copy has a more-specific `share/<os>` override: the local copy is used in its entirety (its own `share/common` only) — no cross-workspace layer fallback, mirroring case 29's shadow principle applied to `share/` |
| 39 | A C++ program (`SRCS` has `.cpp`) links with `${CXX}`, not `${CC}` — exercises real C++ runtime support (exceptions) at link time |
| 40 | A C++ shared library *and* the C++ program consuming it both link with `${CXX}`; the exception is thrown from inside the `.so` itself |
| 41 | `LINK_CXX=yes`: a pure-C module linking a static C++ library fails to link (undefined C++ runtime symbols) without it, and links/runs correctly with it |
| 42 | A broken module + a good module: `bmake` (build) exits non-zero and names the broken module at both framework and workspace level, but the good module still builds (`FAIL_FAST=no`, the default); `FAIL_FAST=yes` stops before the good module is even attempted |
| 43 | Same as 42, for `bmake test`: a genuinely failing atf-c test + a genuinely passing one |
| 44 | Header dependency tracking (gcc/clang `-MMD -MP`): a no-op rebuild recompiles nothing; a module-private header change and a framework-public header reached only via `PREREQS=` (not the consumer's own `src/`) both trigger exactly the affected object to recompile |
| 45 | `bmake` then `bmake SANITIZE=address` actually recompiles (not just relinks stale objects), and the resulting binary genuinely crashes under ASan on a real heap-buffer-overflow; a repeated `bmake SANITIZE=address` recompiles nothing, and dropping back to plain `bmake` recompiles again |
| 46 | `mk.local.mk`'s hook cascade: all four conventional names (`pre.mk`, `pre.${TOOLCHAIN}.mk`, `pre.${TARGET}.mk`, `pre.${TARGET}_${TARGET_ARCH}.mk`) fire when they match (values queried from the real running bmake, not hardcoded), and a hook keyed to a different OS does not |
| 47 | `IMPORT=pkg:<name>` end to end against a real (self-contained, fake) pkg-config `.pc` file: header+lib staging, a plain `LIBS=`-consuming module needs no IMPORT-specific change, only `IMPORT_HEADERS=` is visible (a sibling header in the same prefix is not), and an unresolvable import fails loudly naming what was tried |
| 48 | `IMPORT=` resolution precedence: each ladder step (env/CLI, `mk/` hook, pkg-config, probing) proven individually reachable, then proven to lose to the next higher-precedence step once both are available |
| 49 | Link transitivity, compiled side: a three-level static chain (app → libb → libc) where `app.m` declares only `LIBS=b` -- `libc` still links and runs, pulled in via `libb`'s own recorded `.linkdeps` |
| 50 | Link transitivity, `IMPORT=` side: a fake pkg-config package's real `Libs.private` entry follows it into a consumer that never mentions the private dependency at all |
| 51 | `CXXSTD` defaults to `c++17` — a genuine C++20-only construct (`consteval`) fails under the default and builds/runs correctly with `CXXSTD=c++20` |
| 52 | `OPENMP=yes` builds a real `omp parallel for` program that genuinely uses more than one thread; a compiler that can't accept `-fopenmp` at all (a fake `CC`) gets a clean `.error`, not an opaque compile failure |
| 53 | `WARN=none` suppresses a vendored module's own warnings; `PUBLIC_HEADERS_SYSTEM=yes` on its framework means a consumer in a different framework isn't flooded with warnings from the vendored public header either (`-isystem`) — but the consumer's own code still reports its own warnings normally |
| 54 | Header dependency tracking, the fourth case: a PROMOTED GENERATED header (yacc `-d` output, `INCL=`-promoted) triggers a cross-framework consumer to rebuild when regenerated with different content, same as a hand-written header |
| 55 | `IMPORT=`: `_PKG_CONFIG_EXTRA_DIRS` (settable via a `mk/` hook) is searched for `.pc` files pkg-config's own defaults and `PKG_CONFIG_PATH` would never reach; without it, resolution fails cleanly |
| 56 | `IMPORT=`: `PREREQS=` alone (no `LIBS=`) lets a consumer `#include` the imported header (compiles) but fails to *link* (undefined symbol) — adding `LIBS=` then links and runs, exactly like a compiled library |
| 57 | `IMPORT=`: an externals framework shared via `PARENT_WS`, with a local shadow of the same framework name (both `IMPORT=`-resolved) — the local one wins for compiling, linking, and the actual symbol run, mirroring case 29 for compiled frameworks |
| 58 | The persisted "swap test": the same library, once compiled from source and once `IMPORT=`-resolved, with the consumer module never touched across the swap — both link and run correctly |
| 59 | `IMPORT=` resolution caching, verified with a real call-counting `pkg-config` stub: a build while the package is not yet installed fails and caches nothing, and once it is installed (cache key unchanged) the next build finds it; an unchanged second build then makes no calls, and a changed `PKG_CONFIG_PATH` triggers real re-resolution |
| 60 | `IMPORT=fetch:` (source kind): a genuine fetch+SHA-256-verify+extract+patch+compile+run against a `file://` fixture distfile; `FETCH_PATCHES=` actually changes the fetched source's behavior (verified by running the result); a fingerprint change pointing `FETCH_URL=` at an unreachable path but the same already-downloaded basename still succeeds; multiple `FETCH_URL=` mirrors with the first unreachable fail over to the second |
| 61 | `IMPORT=fetch:`: a `distinfo` SHA-256 that doesn't match the served distfile fails the build cleanly (module/distfile/both hashes named, no corrupted file left behind), and a corrected `distinfo` then builds normally |
| 62 | `IMPORT=fetch-bin:` (binary kind): a prebuilt `lib+header` tree is fetched/verified/extracted and staged via the same `_stage_import:` mechanism `pkg:`/`prefix:` use — no compile step — and a consumer links and runs against it |
| 63 | `IMPORT=pkg:` against a real macOS-style dylib symlink chain (`libfoo.dylib` → `libfoo.34.dylib` → `libfoo.34.3.5.dylib`, matching real MacPorts/Homebrew layouts): both the unversioned and SONAME-equivalent major-version names must stage as valid, non-dangling, non-absolute symlinks, proven by actually running the linked consumer, not just inspecting the staged files (macOS-only; skips elsewhere) |
| 64 | `FETCH_BUILD=cmake`: a real `CMakeLists.txt` fixture project is fetched+patched then built via genuine `cmake -S/-B`/`--build`/`--install` (not skipped — this test caught a real bug: inherited `MAKEFLAGS` silently broke CMake's internal make/ninja invocation, `cmake --build` ran and printed nothing), installed to a local prefix, staged, and linked+run; an unchanged second build does not re-invoke cmake |
| 65 | `FETCH_BUILD=custom`: a hand-rolled `FETCH_BUILD_CMD=` proves the forwarded `CC` and `BMK_FETCH_INSTALL_PREFIX` env vars are real and usable, and that `FETCH_BUILD=custom` with no `FETCH_BUILD_CMD=` fails cleanly naming the missing macro |
| 66 | `REQUIRES=`: a fake pkg-config package proves the `pkg-config --exists` path, a fake shell-script tool on `PATH` proves the `command -v` fallback, and a genuinely missing entry fails cleanly (module + entry named) before any compile is attempted |
| 67 | A program relinks when a `LIBS=` library changes in ANOTHER framework: rebuilds only the library module (never touching the consumer's own directory) and confirms the consumer's link command actually re-runs and the binary's output changes — proven to fail against the pre-fix code (a stale binary silently kept passing) |
| 68 | A `fetch:` module's `SRCS=` names a nested path (mirroring Dear ImGui's own `backends/` layout) and compiles correctly on a genuinely fresh, first extraction |
| 69 | Two real, genuinely fetched `FETCH_BUILD=cmake` modules where one depends on the other via `find_package()` (mirroring `copc-lib`'s real dependency on `laz-perf`): proves `CMAKE_PREFIX_PATH` forwarding lets the dependent's configure step find the dependency, proves the dependent's dashed `LIB=` produces a sanitized, valid `<LIB>_BUILDING` macro, and (macOS) proves no mismatched-deployment-target linker warning |
| 70 | A `fetch:` (source kind) module is a genuine no-op across three consecutive, untouched rebuilds — zero compiler/archiver invocations after the first — and a genuine `FETCH_URL=` change still correctly triggers a real rebuild |
| 71 | A shared `IMPORT=pkg:` resolution uses plain `pkg-config --libs`, not `--libs --static`'s full transitive closure — proven with a fake shared library whose own `.pc` `Libs.private:` names a library that doesn't exist anywhere; the old code would fail to link, the fix links and runs clean |
| 72 | The same Dear ImGui `backends/` layout as case 68, proving the fetched work tree's own root is on the include path automatically (no hand-written `mk/` hook) on a genuinely fresh extraction |
| 73 | A `.linkdeps` consumer two hops removed from where a transitive dependency actually lives (listing only its direct `LIBS=` dependency, never the one two levels down) must both link AND run — proves `-L`/`-Wl,-rpath,` travel with `-l<name>` through `.linkdeps`, not just the bare name |
| 74 | `IMPORT_LIB=none` (header-only import; and it prints no "no resolved library directory" message): a fake `.pc` file whose own `Libs:` field names a nonexistent library proves the lib-staging is genuinely suppressed, not just coincidentally empty, and the consumer builds and runs against the header alone |
| 75 | `IMPORT_HEADERS=` with a glob entry (`gdal_*.h`) stages every match from a fake prefix mixing matching and unrelated headers — only the matches are staged, and the build genuinely links and runs against the real compiled library |
| 76 | `bmake docs` scoping: a framework with `DOCS=no` and one with no public `include/` are both skipped with a clear message each; the workspace landing page lands under `build/docs/`, never colliding with a hand-written `docs/`; the landing page links only frameworks that actually got real docs (skips doxygen if not installed) |
| 77 | `REQUIRES=header:<path>`: a templated/namespaced fake header (not plain C) is found via `CXXFLAGS`, then via `CFLAGS` alone, each building and running correctly, and composes with a plain-name `REQUIRES=` entry in the same list; a missing `-I` and a genuinely nonexistent header path each fail to parse with their own message, before any compile is attempted |
| 78 | `LDFLAGS` contributed by a `mk/local.mk` post-hook reaches the link line (the dedup used to run at parse time, before post-hooks), stays deduplicated against a pre-existing identical `-lm`, and on macOS a `-framework CoreFoundation -framework IOKit` pair survives intact (`otool -L` lists both) — fails against the pre-fix code |
| 79 | A second, unchanged `bmake` is a true no-op: a clean build archives a static library exactly once with no `copy-up collision` (the framework's `build/<key>/include` now exists before any module is parsed, so CFLAGS no longer differ between passes), and the rebuild prints no `staged header`/`resolved via`/`imported` line, runs no compiler/archiver, and writes no file under `build/` — fails against the pre-fix code; and each module is entered exactly once per workspace build (build and copy-up are one `make` invocation) and no `built …` message repeats — fails against the pre-round-5 code |
| 80 | A `fetch:` + `SRCS=` module with `IMPORT_HEADERS=`: `staged header` and `built shared` print exactly once on the first build, nothing on unchanged rebuilds, and once again after a genuine `FETCH_URL=` change (built from the workspace root; a `sleep 1` covers bmake's one-second mtime granularity) |
| 81 | Frameworks A ← B ← C plus an independent D, A fails to compile: B and C are skipped (`framework B skipped: prerequisite A failed`, C also `(root cause: A)`) and never attempted, D still builds, the exit status is non-zero and the summary lists A before the skipped frameworks |
| 82 | `REQUIRES=header:` with the header installed only under a fake tool prefix the compiler doesn't search (prefix list overridden from a `pre` hook) passes; a genuinely absent header still fails, naming the prefixes tried |
| 83 | The `FETCH_BUILD=` deployment-target prologue ends in `;` for `TARGET=linux/freebsd/netbsd/macos` and the `case` that follows it runs under `sh`, `dash` and `bash` (off macOS it was a bare `:`, a dash syntax error on every `FETCH_BUILD=` module) |
| 84 | An `IMPORT=pkg:` whose `.pc` has an empty `Cflags:` (pkg-config's behaviour for a system include dir) still stages `IMPORT_HEADERS=` from `--variable=includedir`; an absent header still fails and names where it looked |
| 85 | An import whose `lib/` holds only symlinks to a versioned real file in another directory stages the real file once with relative links and no self-loop, and the consumer links and runs (host's own `.dylib`/`.so` naming) |
| 86 | `bmake test` alone, after a library source edit, tests the NEW library (atf/kyua; skips without them) |
| 87 | Dot-files and dot-directories under `src/` (macOS AppleDouble `._x.cpp`) are not compiled |
| 88 | A module overwriting its own rebuilt program prints no `copy-up collision`; a second module producing the same program name still does |
| 89 | `PLATFORMS=`/`TOOLCHAINS=` on a module, run against the host's own OS/arch/toolchain: plain, `-`, `!`, `!-` entries, `os_arch` subsets, the validity rule (a negative must narrow a positive), error beating skip across both axes, `REASON.<entry>`, unknown names only warning, `-V` and `clean` never failing, and an excluded module never resolving its `IMPORT=`/`REQUIRES=` |
| 90 | Framework-level exclusion skips the whole framework (no module entered); a framework needing an excluded one is an error naming both while one excluded itself is skipped; exclusions alone leave the exit status 0; a module linking a library its sibling excluded gets an error naming the library |
| 91 | `.tst` test modules (atf/kyua; skips without them): `TEST_PROG=` only, `PROG=` utility + `TEST_PROG=` + `TEST_SRCS=` + scripts, scripts-only; built by a plain `bmake` (a test's compile error fails it) but never copied up into `bin/`; scripts see the utility, another module's program and `BMK_SHAREDIR`; `TEST=` selects by name; a failing script fails the run; both macros without `TEST_SRCS=` is an error; an excluded `.tst` module is skipped |
| 92 | From a clean tree, `bmake test` alone at the workspace builds an untested prerequisite framework that only stages an imported header (the tested framework's test needs it), and `bmake test` at framework scope builds its `PREREQS=` closure (atf/kyua; skips without them) |
| 93 | A static `OPENMP=yes` library used through `LIBS=` by a module that does not set `OPENMP=` links, and `.linkdeps` records `-fopenmp` (skips without an OpenMP runtime) |
| 94 | `bmake run PROGRAM=<x>` runs any program through the build environment: a built program with arguments (from the workspace and from a module dir), the `PATH`/library/`BMK_*` chains, the caller's environment inherited, a program built only in a `PARENT_WS` found, an error naming the chain for a missing one, and an interactive `sh`/`bash`/`zsh` whose own startup file resets `PATH` still ends up with the workspace bin first and the user's rc having run (with a control proving the rc really resets it) |
| 95 | `bmake docs` opt-in knobs: a framework with no public `include/` but `DOC_INPUT_EXTRA=` (local/include + a module's `src/`) is documented, headers only, and `DOC_WARN_IF_UNDOCUMENTED=YES` reports exactly its one undocumented entity; a framework setting nothing gets the unchanged Doxyfile; `DOC_EXTRACT_PRIVATE=YES` is passed through (skips doxygen if not installed) |
| 96 | The product asks the make that is running (`${MAKE}`), never a command named `bmake`: a `PREREQS=` workspace builds, prerequisite headers found, through a copy of the make under another name with a failing `bmake` first on `PATH` that records any call to it (NetBSD has no `bmake`; found building OpenRider) |
| 97 | An unknown `TOOLCHAIN=` (`clang`, `gnu`, `cl`, `bogus`) stops with "no toolchain of that name", lists `llvm`, `gcc`, `msvc` and says which one an alias means (`clang` is `llvm`) instead of "Could not find mk.toolchain.clang.mk"; `TOOLCHAIN=llvm` still works |
| 98 | `IMPORT=fetch:` with a `file://` distfile builds with `curl` and `wget` removed from `PATH` on every host (NetBSD's `ftp` cannot fetch a `file://` URL, so the product copies it), and a missing `file://` distfile fails with "could not fetch any FETCH_URL" |
| 99 | `bmake test` with `TEST_RUNNER=cmd:<program>` runs a `.tst` workspace's tests through the runner: staged with the module's shared library, the utility on `PATH` and `BMK_SHAREDIR`, with the build host's library directories hidden during the run (not on macOS, where SIP strips `DYLD_*`), reports and exit status back; `TEST_RUNNER.<os>-<arch>` wins over `TEST_RUNNER`; a foreign target with no runner stops before building naming the variables to set |
| 100 | Cross builds resolve `IMPORT=pkg:` and `REQUIRES=` in the target sysroot (fake sysroots of `.pc` files, nothing compiled): Linux multiarch for the other architecture and riscv64, FreeBSD `usr/local/libdata`, NetBSD `usr/pkg/lib`, the host's own OS on the other architecture; libdir and includedir in the sysroot; a decoy `.pc` on `PKG_CONFIG_PATH` never leaks, and a native build still reads it; a missing `REQUIRES=` names the sysroot; `TEST_RUNNER=local` exports `QEMU_LD_PREFIX` for a foreign Linux target only (skips without pkg-config) |

| 101 | Import staging stages again when what it staged has gone: a `pkg:` header-only import and a `fetch:` import, the framework's `include/` wiped with the modules' fingerprints intact -- the headers come back and the build names the missing file; an unchanged third build stages nothing (fails against the pre-fix code) |
| 102 | Missing prerequisites stop the build before anything is built, as one list: a `REQUIRES=` package, a `REQUIRES=header:`, an `IMPORT=` that does not resolve, each with how it was looked for -- from the workspace and from a framework; no pkg-config at all is said so, not reported as "not found"; a module whose prerequisite module failed is skipped saying why, and the workspace fails (no `bad number`, no compile cascade) |
| 103 | `make run` after a failed build: a program built in its framework but never copied up (another module failed) is reported with where it is, the failed modules and the log -- not "build first"; a program built nowhere still says build first; the program starts in the directory `run` was typed in (workspace, framework, module), not the workspace root |
| 104 | The same ATF C and C++ test sources (a library's `TESTS_C=`/`TESTS_CXX=`, a `.tst` `TEST_PROG=`) build and run against the installed ATF and against the one Bmake It carries (`BMK_ATF=bundled`; always for MSVC and mingw output), with the same results: passes, a skip, an expected failure, file and regex helpers on a text-mode file; the carried ATF is built from `contrib/` once per framework build root, by the plain build; `atf_utils_fork` passes, except on MSVC/mingw where it fails its test case saying it is not available; a failing check fails `bmake test` with ATF's message; a misspelt `BMK_ATF=` is an error (kyua; skips without it) |

Exit code 77 from `run.sh` is treated as SKIP.

## Coverage plan against the spec (2026-09-02 assessment)

Cross-checked all 38 cases against every confirmed leaf requirement in the
model. Cases 23-38 above closed the gaps found among requirements that are
actually **implemented**:

| ID | REQ |
|----|-----|
| 23 | `linux-libc-default-glibc-req` |
| 24 | `help-target-req` |
| 25 | `add-prereq-add-parent-convenience-targets-req` (the `add-parent` half) |
| 26 | `install-requires-prebuilt-target-req-v2` (the negative path specifically — test 17 only covered the success path) |
| 27 | `no-workspace-level-share-source` (NREQ). `no-identitycard-special-file` is already covered implicitly: every case from 01 on builds a real framework using nothing but `makefile`+`PREREQS=`. |
| 28 | `headers-resolved-from-source-req`, parent-only case |
| 29 | `headers-resolved-from-source-req`, local-shadows-parent case |
| 30 | `add-prereq-add-parent-convenience-targets-req` (the `add-prereq` half, text-editing behavior only) |
| 31 | `run-target-req`, `run-target-any-workspace-dir-req` |
| 32 | `add-prereq-add-parent-convenience-targets-req` × `headers-resolved-from-source-req`, same-workspace case (no existing case exercised this topology — 11 only compiles, never links+runs) |
| 33 | `add-prereq-add-parent-convenience-targets-req` × `headers-resolved-from-source-req`, parent-only case, via `add-prereq` rather than hand-written `PREREQS=` |
| 34 | `add-prereq-add-parent-convenience-targets-req` × `headers-resolved-from-source-req`, local-shadows-parent case, via `add-prereq` |
| 35 | `link-time-not-yet-built-guard-req` |
| 36 | `copy-up-collision-diff-aware-req`, genuine (non-overlay) collision case |
| 37 | `share-overlay-copy-order-req`, full layer-presence matrix (previously only ever exercised in the trivial "all three layers agree" shape, never per-layer-unique or partial-override combinations) |
| 38 | `headers-resolved-from-source-req`'s "local wins entirely, no merging" principle, applied to `share/` instead of headers/libs — previously untested for this subsystem specifically |

`run`, `add-prereq`, and the link-time not-yet-built guard are now
implemented (2026-09-02) — mk.common.mk (shared by all four roles),
mk.framework.mk, and mk.prog.mk/mk.lib.mk respectively — closing the
exclusions noted in the prior assessment. copy-up is now diff-aware too
(mk.prog.mk/mk.lib.mk/mk.framework.mk copy-up targets, via the new
scripts/diff-aware-copy.sh). Still excluded, because still
unimplemented: cross-toolchain paths, binary packaging, and `.depend`/`-MD`
tracking — none of these have real behavior yet, so no test can validate
them; they belong with those features, not before them.

Note on the link-time guard's scope: it checks that each `LIBS=` entry's
build artifact *exists* before linking (per the confirmed REQ). It
deliberately does not attempt an "is it up to date" staleness check — that
would need real source-to-artifact dependency tracking (the still-unimplemented
`-MD` req) to be precise; a coarse mtime heuristic without it would risk
spurious failures on legitimate builds. Staleness detection should ride on
top of `-MD` tracking once that lands, not ship as a guess now.

Note on the diff-aware copy-up's scope: it covers the three `copy-up:`
targets (module→framework bin/lib, framework→workspace bin/lib/share) —
these are where two *independently built* things can genuinely collide.
The framework-local `share/common → share/<os> → share/<os>_<arch>`
specificity cascade inside `_aggregate:` is deliberately left on plain
`cp -a`, unchanged: per the confirmed REQ, a more-specific layer
overwriting a less-specific one there is expected, by-design behavior and
must never warn, which is exactly what leaving it alone already gives.

Note on cases 37/38: `TARGET=`/`TARGET_ARCH=` are lazily-assigned (`=`) in
mk.common.mk, so `bmake -V TARGET` prints them unexpanded (a bmake quirk —
`:=`-built variables like `OS_ARCH` resolve fully, plain `=` ones don't).
Both tests derive TARGET/TARGET_ARCH by splitting `bmake -V OS_ARCH`
instead, same as case 13-target-key already relies on.

Lower priority, noted but not designed as archives:

- **`debug-release-via-native-bsd-flags-req`** — `DEBUG_FLAGS=-g` should reach the actual compile line and no project-specific `MODE=` should exist. Could fold into a `CFLAGS`-inspection assertion similar to test 21.
- **`module-name-case-sensitivity-req`** — the requirement is "no enforcement," which is filesystem-dependent and not meaningfully assertable in a portable test; skip (exit 77) on case-insensitive filesystems if ever written.
- **`shlib-major-minor-cross-platform-emission-req`**, ELF half — the FreeBSD/Linux symlink-chain behavior (as opposed to the macOS dylib path test 09 already covers) can't be tested until cross-compilation is real; it's a stub today, same as the toolchain paths.
- **`build-system-self-test-harness-req`** — satisfied by this suite's own existence; a test of the test harness would be diminishing returns.
- **`no-four-level-header-visibility`** (NREQ) — already implicitly covered by test 11 asserting exactly three include paths; not worth a separate case.
