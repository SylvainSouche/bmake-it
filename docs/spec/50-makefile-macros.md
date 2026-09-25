# Bmake It — 50: Makefile Macro Reference

Status: DRAFT, synthesized from confirmed `project-model/req/` objects.
Quick-reference for every macro across all four makefile roles. "Reused
native" = an existing BSD make variable, used unchanged. "New" = has no
BSD-make-native equivalent, introduced by this project.

## Workspace makefile (`.include <mk.workspace.mk>`)

| Macro | Meaning | Status |
|---|---|---|
| `PARENT_WS=<path1> <path2> ...` | Ordered, space-delimited list of **absolute** paths to parent workspaces, searched in order for anything not found locally | New (`REQ-workspace-parent-macro-absolute-req`) |

## Framework makefile (`.include <mk.framework.mk>`)

| Macro | Meaning | Status |
|---|---|---|
| `PREREQS=<fw1> <fw2> ...` | **Mandatory**, even empty (`PREREQS=`). Ordered, space-delimited list of frameworks this one may `LIBS=`-link against and see the public headers of. All entries implicitly public — no per-entry visibility qualifier. Also doubles as the framework auto-discovery signal | New (`REQ-framework-prereqs-macro-req`, `REQ-prereqs-mandatory-even-empty-req`) |
| `PUBLIC_HEADERS_SYSTEM=yes` | This framework's public headers reach every `PREREQS=`-consumer via `-isystem` instead of `-I` — for a framework that wraps or vendors third-party code, so a consumer isn't flooded with warnings originating from headers it doesn't own | New (`REQ-public-headers-system-req`) |

## Module makefile — executable (`.include <mk.prog.mk>`)

| Macro | Meaning | Status |
|---|---|---|
| `PROG=<name>` | Output executable name. Defaults to the module directory name (`.m` stripped) if unset | New (`REQ-prog-lib-default-to-module-name-req`) |
| `LIBS=<lib1> <lib2> ...` | Space-delimited libraries to link against (dev and/or system). **Link-time only** — has no effect on header visibility | New, replaces an earlier `LINK_WITH=` design (`REQ-libs-macro-link-only-headers-via-prereqs-req`) |
| `LINK_CXX=yes` | Force the final link to use `${CXX}` even though `SRCS` is all-C. See below | New (`REQ-cxx-link-driver-selection-req`) |

## Module makefile — library (`.include <mk.lib.mk>`)

| Macro | Meaning | Status |
|---|---|---|
| `LIB=<name>` | Output library base name. Defaults to the module directory name if unset | New (`REQ-prog-lib-default-to-module-name-req`) |
| `LIB_SHARED=YES\|NO` | `YES` (default): shared library. `NO`: static/archive | New (`REQ-lib-shared-defaults-yes-req`, `REQ-lib-shared-no-is-static-req`) |
| `LIBS=<lib1> <lib2> ...` | Same as above — link-time only | New |
| `LINK_CXX=yes` | Same as above — forces `${CXX}` for the shared-library link | New (`REQ-cxx-link-driver-selection-req`) |
| `INCL=<header1> <header2> ...` | Names which of this module's *generated* headers get promoted to public (copied to the framework's `build/<KEY>/include/`). Unlisted generated headers stay module-private | New (`REQ-incl-macro-promotes-generated-headers-req`) |
| `IMPORT=pkg:<name>\|prefix:<dir>\|fetch:<label>\|fetch-bin:<label>` | Import a prebuilt library instead of compiling `SRCS` — resolved via pkg-config, a literal prefix, env/`mk/`-hook overrides alone, or a fetched distfile (source or prebuilt). See `25-imported-libraries.md` and `26-fetched-external-sources.md` | New (`REQ-import-resolution-ladder-req`, `REQ-fetch-import-source-req`, `REQ-fetch-import-binary-req`) |
| `IMPORT_HEADERS=<name1> <name2> ...` | Exactly which headers/subdirectories to stage from the resolved import — never the whole prefix | New (`REQ-import-staging-req`) |
| `FETCH_URL=<url> [<url> ...]` | One or more full URLs to the same distfile, tried in order until one succeeds. Only meaningful with `IMPORT=fetch:`/`fetch-bin:`. See `26-fetched-external-sources.md` | New (`REQ-fetch-import-source-req`) |
| `FETCH_PATCHES=<name> [<name> ...]` | Files under this module's own `patches/`, applied in order via `patch -p1` against the extracted work tree. Only meaningful with `IMPORT=fetch:`/`fetch-bin:` | New (`REQ-fetch-import-source-req`) |
| `SHLIB_MAJOR=<n>` | Major version for the shared library. Reused directly from real BSD `bsd.lib.mk` | Reused native (`REQ-shlib-major-minor-cross-platform-emission-req`) |
| `SHLIB_MINOR=<n>` | Optional minor version | Reused native |

`SHLIB_MAJOR`/`SHLIB_MINOR` is the single cross-platform source of
truth: on FreeBSD/Linux it produces `libfoo.so.MAJOR[.MINOR]` with the
standard symlink chain (unchanged `bsd.lib.mk` behavior); on macOS it
produces `libfoo.MAJOR.dylib` with a matching symlink **and** feeds the
same numbers into the linker's native `-compatibility_version`/
`-current_version` flags, since that's macOS's actual ABI-compatibility
mechanism, not just a filename convention.

## Link driver selection (`mk.prog.mk`/`mk.lib.mk`)

The final link step uses `${CXX}` — not `${CC}` — whenever `SRCS`
contains a `.cc`/`.cpp`/`.cxx` source, or `LINK_CXX=yes` is set
explicitly; otherwise it uses `${CC}` (`REQ-cxx-link-driver-selection-req`).
Per-source compilation was already language-correct; only the *final*
link (and, for a library, the shared-object link) previously always used
`${CC}` regardless of language, which left C++ runtime support symbols
(exception handling, RTTI, etc.) undefined for any C++ program or shared
library. `LINK_CXX=yes` is the explicit override for the one case
auto-detection can't see: a module whose own `SRCS` is entirely C, but
that links a static C++ library (`LIBS=`) and therefore still needs the
C++ runtime pulled in at link time. Like `TESTS_CXX=`/`LIB=`/`PROG=`,
`LINK_CXX=` must be set **before** `.include`ing `mk.prog.mk`/`mk.lib.mk`.

Mirrors real `bsd.init.mk`'s own `_CCLINK` mechanism (auto-detect from
`SRCS`, explicit `PROG_CXX=` override) without including any of its code
— Bmake It's `mk.prog.mk`/`mk.lib.mk` never `.include` a real `bsd.*.mk`
file at all, only Bmake It's own `mk.*.mk` role files, so the logic is
reimplemented as Bmake It's own internal `_CCLINK` variable. The naming
diverges deliberately: `PROG_CXX=` means "use this name instead of
`PROG=`", a different concept from `LINK_CXX=yes`.

## Local customization (`mk/` directories)

A workspace, framework, or module may carry its own `mk/` subdirectory,
consulted for eight conventionally-named hook files — `pre.mk`/`local.mk`,
each with unconditional, `${TOOLCHAIN}`-conditional (`pre.${TOOLCHAIN}.mk`),
`${TARGET}`-conditional (`pre.${TARGET}.mk`), and
`${TARGET}_${TARGET_ARCH}`-conditional (`pre.${TARGET}_${TARGET_ARCH}.mk`,
same naming as `share/<os>_<arch>` — for a path that differs by arch on
one OS, e.g. Homebrew's `/opt/homebrew` on arm64 vs `/usr/local` on
amd64, which `${TARGET}` alone can't express) variants
(`REQ-local-mk-hook-files-and-cascade-order-req`,
`REQ-local-mk-arch-variant-req`). No combined toolchain+target_arch
filename — the realistic need is covered by target_arch alone, and the
separate `${TOOLCHAIN}`-conditional variant already covers toolchain
overrides independently. `pre.mk` is included
before a role file computes its defaults (e.g. before `mk.docs.mk` derives
`DOC_PROJECT_NAME=` — the mechanism `70-documentation-generation.md` uses
for project-metadata overrides); `local.mk` after.

Visibility cascades outward-in, and **every** matching level is included,
not just the most specific (`REQ-per-level-local-mk-directory-req`):

| From | Sees `mk/` at |
|---|---|
| Workspace | its own, then every `PARENT_WS`'s |
| Framework | workspace, then its own |
| Module | workspace, then framework, then its own |

Typical use: a module's own `mk/local.${TOOLCHAIN}.mk` appending an extra
`CFLAGS` for one specific toolchain, without touching the shared
`mk/*.mk` role files.

## Test declarations (`.include <mk.test.mk>`, included by `mk.prog.mk`/`mk.lib.mk`)

| Macro | Meaning | Status |
|---|---|---|
| `TESTS_CXX=<name1> <name2> ...` | atf-c++ test cases, sources at `tests/<name>.cpp`. Must be set **before** `.include`ing `mk.lib.mk`/`mk.prog.mk` — bmake evaluates macro checks in file order, so a declaration placed after the `.include` is invisible to it, same convention as `LIB=`/`PROG=` | New (`REQ-unit-test-feature-for-built-software-req`) |
| `TESTS_C=<name1> <name2> ...` | atf-c test cases, sources at `tests/<name>.c` | New |
| `TESTS_SH=<name1> <name2> ...` | atf-sh script tests, staged from `tests/<name>.sh` | New |

Full detail, including the `test`/`test-all` targets: `80-unit-testing.md`.

## Documentation-generation metadata (`.include <mk.docs.mk>`)

| Macro | Meaning | Status |
|---|---|---|
| `DOC_PROJECT_NAME=`, `DOC_PROJECT_VERSION=`, `DOC_PROJECT_BRIEF=`, `DOC_LOGO=`, `DOC_LICENSE_NOTICE=` | Override the auto-detected Doxygen project-identity fields (from `VERSION`/`LICENSE`/`docs/logo.*`); set in a `pre.mk` (above) | New (`REQ-doc-project-metadata-conventions-req`) |

Full detail: `70-documentation-generation.md`.

## Reused BSD-make-native variables (apply at any module level)

| Variable | Meaning |
|---|---|
| `CFLAGS`, `CXXFLAGS`, `LDFLAGS`, `YFLAGS`, `LFLAGS` | Extra compile/link options, appended via `+=` — no `LOCAL_*FLAGS` wrapper (`REQ-flags-reuse-bsd-native-vars-req`) |
| `DEBUG_FLAGS` | Debug symbol generation (`-g`), no separate `MODE=` switch (`REQ-debug-release-via-native-bsd-flags-req`) |
| `TARGET`, `TARGET_ARCH` | Target OS/arch on the `make` command line (`REQ-target-selection-uses-bmake-native-vars-req`) |
| `DESTDIR`, `PREFIX` | Install staging root / final path, for `make install` (`REQ-destdir-prefix-confirmed-req`) |

## New, project-specific variables (summary)

| Variable | Introduced because |
|---|---|
| `TOOLCHAIN=gcc\|llvm` | No BSD-make-native concept of a toolchain *bundle* (compiler+linker+archiver as one selectable unit) (`REQ-toolchain-cli-variable-req`) |
| `SANITIZE=<name>[,<name>...]` | No BSD-make-native concept of sanitizer instrumentation as a selectable unit spanning `CFLAGS`/`CXXFLAGS`/`LDFLAGS`; see `40-cli-reference.md` (`REQ-sanitizer-support-req`) |
| `CXXSTD=<std>` | C++ language standard, default `c++17`. `-std=<std>` (gcc/clang) or `/std:<std>` (msvc, same spelling — no translation table needed) (`REQ-cxxstd-macro-req`) |
| `OPENMP=yes\|no` | OpenMP support, default `no`. Real `-fopenmp` acceptance is *probed* (compile-only check), not assumed — a compiler that can't actually provide it is a parse-time `.error`, not an opaque failure deep in the build (`REQ-openmp-macro-req`) |
| `WARN=none` | Suppresses this module's own compile warnings (`-w`, a genuine master switch) — for a module compiling vendored third-party source. `-Wall -Wextra` is the default baseline otherwise (`REQ-warn-macro-req`) |
| `PUBLIC_HEADERS_SYSTEM=yes` (framework makefile) | This framework's public headers reach any `PREREQS=`-consumer via `-isystem`, not `-I` — pairs with `WARN=` for a framework that wraps/vendors third-party code (`REQ-public-headers-system-req`) |
| `PARENT_WS`, `PREREQS`, `PROG`, `LIB`, `LIBS`, `LIB_SHARED`, `INCL` | Domain-specific concepts (workspace parenting, framework prereqs, module identity/linking/header-promotion) that have no BSD-make equivalent at all |
