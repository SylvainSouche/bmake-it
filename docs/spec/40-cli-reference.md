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

## Sanitizers

```
make all SANITIZE=address,undefined
make test SANITIZE=address
```

**`SANITIZE=<name>[,<name>...]`** selects compiler/linker sanitizer
instrumentation (`address`, `undefined`, `thread`, `memory`, `leak`) —
a plain compile/link-flag concern via the shared `CFLAGS`/`CXXFLAGS`/
`LDFLAGS`, so it composes with both `run` and `test` without either
target needing its own sanitizer-specific logic
(`REQ-sanitizer-support-req`).

- **Mutual exclusion**: `address`, `thread`, and `memory` instrument the
  runtime in incompatible ways — at most one of the three. Combining any
  two fails loudly at parse time (`SANITIZE=address,thread` → an
  explicit `.error`, not a cryptic compiler/linker failure). `undefined`
  and `leak` compose freely with any of them.
- **Toolchain limits, documented not silently degraded**: gcc/clang on
  Linux/macOS/BSD have full support. MSVC supports `address` only —
  requesting anything else under `TOOLCHAIN=msvc` fails loudly with the
  same discipline. mingw/Cygwin gcc support is real but patchy
  per-sanitizer; not blocked, not guaranteed.
- **`undefined` is fatal on first hit**: UndefinedBehaviorSanitizer's own
  default is to log a diagnostic and keep running, which would let a
  real bug sit unnoticed in stderr while `test` reports "passed" —
  found empirically. `SANITIZE=undefined` therefore also sets
  `-fno-sanitize-recover=undefined`, so a violation aborts the process
  (matching AddressSanitizer's own default behavior) rather than being
  silently survivable.
- **Workspace/framework scope**: `SANITIZE=` set at the workspace or
  framework level is forwarded through the recursive `all`/`test`
  targets to every module — not just when invoked directly inside a
  module directory. See `80-unit-testing.md` for the `test` recursion
  and dashboard specifically. Note the same rebuild caveat as any other
  flag change — see "Rebuild before testing" there.

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
| `docs` | Generates Doxygen documentation — just the enclosing framework from within a framework, or every framework plus a workspace aggregation page from the workspace root (`REQ-doc-generation-invocation-scope-req`). See `70-documentation-generation.md` |
| `test` | Builds and runs this module's (or, at framework/workspace scope, every module's) declared `TESTS_CXX=`/`TESTS_C=`/`TESTS_SH=` tests via Kyua; writes a JUnit XML report; exits non-zero on any failure (`REQ-unit-test-feature-for-built-software-req`). See `80-unit-testing.md` |

## Reports and CI integration

```
make all REPORT=yes                        # workspace build dashboard
make test REPORT=yes                        # workspace test dashboard
make all FAIL_FAST=yes                       # stop at the first broken module
make test TEST=hello_test FW=Hello REPORT=yes  # one test, one dashboard
```

- **`REPORT=<yes|no>`** (default `no`): purely about the dashboard.
  `REPORT=yes` on a workspace/framework `all` builds
  `build-report/index.html` (`BUILD_REPORT_DIR=`, default `build-report`)
  listing every framework/module with PASS/FAIL and a link to its
  `build.log`; on `test`, it additionally builds each module's HTML
  report and a workspace-level `test-report/index.html`
  (`TEST_REPORT_DIR=`, default `test-report`) — see `80-unit-testing.md`.
  With `REPORT` unset, the run still happens and logs are still written
  (see below), just without the dashboard step
  (`REQ-build-workspace-aggregation-req-v2`, `REQ-test-workspace-aggregation-req`).
- **`FAIL_FAST=<yes|no>`** (default `no`): whether one module's build or
  test failure stops a workspace/framework run before every other module
  gets attempted. Default is to keep going — a build error in one module
  must not prevent the rest of the workspace from building, and a test
  failure must not prevent the rest of the suite from running, unless
  `FAIL_FAST=yes` is explicitly given. Independent of `REPORT=`: whether
  a run continues past a failure and whether a dashboard gets built from
  what happened are two separate questions. A bare single-module `bmake
  all`/`test` (not via workspace/framework recursion) is unaffected
  either way — there's nothing else to continue past
  (`fail-fast-independent-of-report`).
- **Where logs live**: a workspace/framework `all` always writes
  `<module>/build/<KEY>/build.log` (and a per-framework rollup at
  `<framework>/build/<KEY>/build.log`) regardless of `REPORT=` — console
  output is unchanged (`tee`'d, not replaced). `test` always writes
  `<module>/build/<KEY>/test-results.xml` (JUnit) regardless of
  `REPORT=`; Kyua's own results store (`~/.kyua/store/`) also has every
  run's raw output. `REPORT=yes` is what turns those into a browsable
  dashboard, not what creates them in the first place.
- **`TEST=<name>`**, **`FW=<name>`**: narrow a `test` run to one test
  (and, at workspace level, one framework) — see `80-unit-testing.md`.
- **What Bmake It does not do**: fetch/pull changes from version control,
  or publish/serve the generated reports anywhere. It produces
  `build-report/`, `test-report/`, and the underlying logs as plain
  files on local disk; an external integration-manager/CI process is
  expected to own retrieving code and making those files reachable (a
  LAN site, an artifact store, whatever fits) (`CON-ci-integration-scope-boundary`).

## Discovery (no explicit listing required)

- **Workspace → frameworks**: any immediate subdirectory containing a
  `makefile` that declares `PREREQS=` is auto-discovered as a framework.
- **Framework → modules**: any immediate `*.m`-suffixed subdirectory is
  auto-discovered as a module.

Neither requires an explicit `SUBDIR=`-style list — same philosophy as
`src/` source auto-discovery (`REQ-modules-and-frameworks-auto-discovered-req`).
