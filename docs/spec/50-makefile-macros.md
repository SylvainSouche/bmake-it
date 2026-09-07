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

## Module makefile — executable (`.include <mk.prog.mk>`)

| Macro | Meaning | Status |
|---|---|---|
| `PROG=<name>` | Output executable name. Defaults to the module directory name (`.m` stripped) if unset | New (`REQ-prog-lib-default-to-module-name-req`) |
| `LIBS=<lib1> <lib2> ...` | Space-delimited libraries to link against (dev and/or system). **Link-time only** — has no effect on header visibility | New, replaces an earlier `LINK_WITH=` design (`REQ-libs-macro-link-only-headers-via-prereqs-req`) |

## Module makefile — library (`.include <mk.lib.mk>`)

| Macro | Meaning | Status |
|---|---|---|
| `LIB=<name>` | Output library base name. Defaults to the module directory name if unset | New (`REQ-prog-lib-default-to-module-name-req`) |
| `LIB_SHARED=YES\|NO` | `YES` (default): shared library. `NO`: static/archive | New (`REQ-lib-shared-defaults-yes-req`, `REQ-lib-shared-no-is-static-req`) |
| `LIBS=<lib1> <lib2> ...` | Same as above — link-time only | New |
| `INCL=<header1> <header2> ...` | Names which of this module's *generated* headers get promoted to public (copied to the framework's `build/<KEY>/include/`). Unlisted generated headers stay module-private | New (`REQ-incl-macro-promotes-generated-headers-req`) |
| `SHLIB_MAJOR=<n>` | Major version for the shared library. Reused directly from real BSD `bsd.lib.mk` | Reused native (`REQ-shlib-major-minor-cross-platform-emission-req`) |
| `SHLIB_MINOR=<n>` | Optional minor version | Reused native |

`SHLIB_MAJOR`/`SHLIB_MINOR` is the single cross-platform source of
truth: on FreeBSD/Linux it produces `libfoo.so.MAJOR[.MINOR]` with the
standard symlink chain (unchanged `bsd.lib.mk` behavior); on macOS it
produces `libfoo.MAJOR.dylib` with a matching symlink **and** feeds the
same numbers into the linker's native `-compatibility_version`/
`-current_version` flags, since that's macOS's actual ABI-compatibility
mechanism, not just a filename convention.

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
| `PARENT_WS`, `PREREQS`, `PROG`, `LIB`, `LIBS`, `LIB_SHARED`, `INCL` | Domain-specific concepts (workspace parenting, framework prereqs, module identity/linking/header-promotion) that have no BSD-make equivalent at all |
