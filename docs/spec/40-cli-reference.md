# Bmake It — 40: `make` CLI Reference

Status: DRAFT, synthesized from confirmed `project-model/req/` objects.

## Target selection

```
make TARGET=freebsd TARGET_ARCH=amd64 TOOLCHAIN=gcc
```

- **`TARGET=`** (OS) and **`TARGET_ARCH=`** (architecture) — reuse real
  BSD make's own cross-build variable names, matching FreeBSD's own
  cross-build convention, rather than inventing new ones
  (`REQ-target-selection-uses-bmake-native-vars-req`). Unspecified =
  current host.
- **`TOOLCHAIN=`** (`gcc`|`llvm`) — new, project-specific (no BSD-make-
  native equivalent exists). Unspecified = `llvm` (the default)
  (`REQ-toolchain-cli-variable-req`). Setting it `.include`s a dedicated
  `mk.toolchain.<name>.mk`, which sets the underlying `CC`/`CXX`/`LD`/
  `AR`/`AS` as a coherent bundle — following the same role-specific-
  include pattern as `mk.workspace.mk`/`mk.framework.mk`/`mk.prog.mk`/
  `mk.lib.mk` (`REQ-toolchain-triggers-dedicated-mk-file-req`). These
  underlying variables remain individually overridable afterward via
  ordinary make variable precedence, for mixed setups (e.g. clang + GNU
  `ld`).

Together these three variables determine the full compound target key
(`10-directory-layout.md`).

## Debug/release and extra compile flags

No new abstraction — everything here reuses BSD make's own native
variables directly, appended via `+=` in a module's makefile:

- **Debug vs. release**: `DEBUG_FLAGS` (conventionally `-g`) and an
  optimization-level flags variable (exact name — `COPTFLAGS` vs.
  `CFLAGS`-family — pending the same empirical `bsd.*.mk` check as the
  caching mechanism). No `MODE=debug|release` wrapper
  (`REQ-debug-release-via-native-bsd-flags-req`). Consistent with
  `REQ-variant-out-of-scope-for-dirtree`: switching variant and
  rebuilding overwrites the existing target output in place, no separate
  directory.
- **Extra compile/link options**: `CFLAGS`, `CXXFLAGS`, `LDFLAGS`,
  `YFLAGS`, `LFLAGS` — BSD make's own native variables, unchanged. No
  `LOCAL_*FLAGS`-style wrapper macros the way real `mkmk` had
  (`REQ-flags-reuse-bsd-native-vars-req`).

## `make` targets

| Target | Behavior |
|---|---|
| (default) | Fused compile+link build of the current directory's scope (module/framework/workspace) for the selected target |
| `clean` | Removes the current/selected target's `build/<KEY>/` subtree only, by default. `TARGET=all` is a special value that wipes `build/` output for *every* target at once (`REQ-clean-target-scope-req`) |
| `install` | `make install DESTDIR=<staging-root> PREFIX=<final-path>` — BSD make's own native `DESTDIR`/`PREFIX`, unchanged. Copies `build/<KEY>/{bin,lib,share}` into `$(DESTDIR)$(PREFIX)/{bin,lib,share}` (`REQ-destdir-prefix-confirmed-req`). Requires the target to already be built — does not implicitly trigger a build (`REQ-install-requires-prebuilt-target-req`). Cross-filesystem `DESTDIR` installs are deferred |
| `pkg`, `deb`, `rpm`, `msi` | Binary packaging targets. Each stages `distrib/<KEY>/` by internally invoking the equivalent of `install DESTDIR=distrib/<KEY>` (reusing the install mechanism, not a separate copy step — `REQ-packaging-invokes-install-into-distrib-req`), then builds the actual package artifact from that staged tree. One named target per format, not a single parameterized target (`REQ-packaging-per-format-targets-req`) |
| `port` | **Categorically different** from the binary-package targets above: produces a source-based BSD-ports-style recipe (port `Makefile`, `distinfo`, patches, `pkg-plist`) for the ports system to fetch and build itself — no pre-built binary is staged or embedded (`REQ-port-target-is-source-recipe-not-binary-package-req`). Exact generation mechanism is deferred to a later phase (`REQ-make-port-deferred-req`) |
| `add-prereq FW=<name>` | Convenience target: appends `<name>` to the current framework's `PREREQS=`. Pure text-editing convenience, does **not** resolve or search for anything (distinct from the rejected `mkGetPreq`/`mkCopyPreq`) (`REQ-add-prereq-add-parent-convenience-targets-req`) |
| `add-parent WS=<abs-path>` | Convenience target: appends `<abs-path>` to the workspace's `PARENT_WS=` |

## Discovery (no explicit listing required)

- **Workspace → frameworks**: any immediate subdirectory containing a
  `makefile` that declares `PREREQS=` is auto-discovered as a framework.
- **Framework → modules**: any immediate `*.m`-suffixed subdirectory is
  auto-discovered as a module.

Neither requires an explicit `SUBDIR=`-style list — same philosophy as
`src/` source auto-discovery (`REQ-modules-and-frameworks-auto-discovered-req`).
