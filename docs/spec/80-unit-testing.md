# Bmake It — 80: Unit Testing

Status: DRAFT, synthesized from confirmed `project-model/req/` objects.
Implemented in `mk/mk.test.mk`, verified end-to-end against MacPorts
atf 0.21 / kyua 0.14.1 on `examples/myworkspace`.

## Tool and rationale

Tests are written against **ATF** (Automated Testing Framework:
`atf-c`/`atf-c++` for compiled cases, `atf-sh` for script cases) and run
via **Kyua**, natively — Bmake It's own `mk.test.mk` provides the
`bsd.test.mk`-style declarative registration (`TESTS_C=`/`TESTS_CXX=`/
`TESTS_SH=`), no CMake/CTest dependency. Bmake It is itself a CMake
alternative; wrapping CMake/CTest for its own test feature would
contradict that (`REQ-unit-test-atf-kyua-adoption-req`).

ATF/Kyua is native to the bsd-make lineage (NetBSD originated it; FreeBSD
also uses it for `/usr/tests`) and spans compiled and script tests under
one model, matching CTest's own agnostic-to-what-produces-pass/fail
design. Known tradeoff, accepted on a try-first basis: much weaker
cross-platform packaging outside the BSDs than gtest/Catch2 — MacPorts
carries it (see below); a Linux/Windows host without a packaged ATF/Kyua
is a real gap, not yet worked around.

As with documentation generation, the mechanism is pluggable per
language: extending Bmake It's language support must be able to bring
that language's own appropriate mainstream test tool rather than being
forced through ATF (`REQ-unit-test-per-language-tool-pluggable-req`).

## Declaring tests

In a module's makefile, **before** `.include "mk.lib.mk"` /
`mk.prog.mk"` (declaration order matters — see `50-makefile-macros.md`):

```
TESTS_CXX = greet_test
```

Sources are looked up by convention: `tests/<name>.cpp` (atf-c++),
`tests/<name>.c` (atf-c), `tests/<name>.sh` (atf-sh). What a compiled
test links against to reach the code under test depends on the module
kind: a **library module** (`LIB=`) links its real built library
(`-l${LIB}`), no separate `LIBS=` entry needed; a **program module**
(`PROG=`) has no such linkable artifact, so its test instead links
directly against the module's own already-compiled objects from the
normal build, excluding the entry-point object (conventionally
`main.o`) so the test binary supplies its own `main` via
`ATF_INIT_TEST_CASES`/`ATF_TP_ADD_TCS` rather than colliding with the
module's own entry point.

All three kinds are registered in a generated `Kyuafile` and run via
`kyua test`, agnostic to which kind produced the pass/fail
(`REQ-unit-test-feature-for-built-software-req`).

## Test modules (`.tst`)

Implemented in `mk/mk.tst.mk` and the framework's `test` target, covered
by `tests/cases/91-tst-modules` (`tst-test-modules-dec`,
`tst-module-layout-req`, `tst-scripts-are-tests-req`, `tst-test-prog-req`,
`tst-test-srcs-req`, `tst-test-environment-req`).

The flat `tests/<name>.cpp` form above is the cheap default and stays.
Its limit is that a loose test source has no makefile, so no build
directives: no per-test `LIBS=`/flags, no second source file, no helper
shared between tests, and a script test cannot be paired with a helper
program. For a project that outgrows that, a test can instead be a
**`.tst` module** — the same idea as Dassault Systèmes' mkmk, where a
framework `FrameworkXYZ` has a sibling of test modules.

```
GIS/
  libgdal.m/
  raster.tst/               a test module, same shape as a .m module
    makefile                PROG=raster_util  TEST_PROG=raster_test  LIBS=geo
    src/                    compiled sources
    testcases/              *.sh -- each one is a test
      warp.sh
      thin.sh
```

- **Where:** inside the framework, beside the `.m` modules, discovered the
  same way (a `*.tst` suffix). A nested test framework was considered
  and rejected: it would need recursive discovery and its own `PREREQS=`,
  where a `.tst` module inherits the framework's `PREREQS=`/`LIBS=`/header
  visibility as-is.
- **Built, never shipped** (`tst-modules-built-not-shipped-dec`): a plain
  `bmake` builds `.tst` modules too, after the `.m` modules, so a compile
  error in a test surfaces at build time like any other module's. They take
  no part in `copy-up`, `install` or `distrib`: their programs stay in the
  module's own `build/<KEY>/` and never reach the framework's or workspace's
  `bin/`. `bmake test` is what runs them.
- **Scripts are the tests.** Every `testcases/*.sh` is auto-discovered
  (like `src/`; no `TESTS_SH=` list) and registered with Kyua as an
  atf-sh test program, so one program can serve many scenarios.
- **Programs.** `PROG=<name>` builds a *utility* the scripts call; it is
  built but not registered. `TEST_PROG=<name>` — named like `PROG=`, not a
  flag — builds a program that *is* an ATF test program and is registered.
  A module may set both and have any number of scripts.
- **Finding the helper.** A module's built programs and its scripts are
  placed in one test directory (`build/<KEY>/tests/`, as for the flat
  form), so a script reaches its utility with `$(atf_get_srcdir)/<name>`.
- **Test environment** (`tst-test-environment-dec`,
  `tst-test-environment-req`). A test script sees the *resulting* build
  output, not just its own module or framework: every executable present
  in the resulting `bin` is on its `PATH`, whichever framework built it,
  and the resulting `share` directory is reachable for shipped helper
  scripts (the variable naming it is decided at implementation). Using an
  executable from a framework outside the test's `PREREQS=` is **bad
  practice, documented as such, and not an error** — nothing tracks it,
  so there is no build-order guarantee: such an executable may be absent
  or stale depending on what was built first. That is the cost of the
  practice, not something Bmake It diagnoses.
- **Helper scripts are shipped, not hidden.** If a test script needs a
  script to do some of its work, that script is shipped the usual way
  (a framework's `share/` overlay, or an executable in `bin/`), not kept
  private inside a test module's `testcases/`, which holds tests only.
- **Limit.** A `.tst` module can link a library module, but not a *program*
  module's objects minus `main.o` — that is what the in-module `tests/`
  form does for a `PROG=` module (Viewer's tests in lasviewer). A program's
  internals are tested in-module, or by moving the logic into a library.

**Sources when both are set** (`tst-test-srcs-req`, decided at
implementation, flagged for review): `TEST_PROG=` alone builds the test
program from all of `src/` (or `TEST_SRCS=`); with `PROG=` also set,
`TEST_SRCS=` names the test program's sources (relative to `src/`) and
`PROG` is built from the rest. Setting both without `TEST_SRCS=` is an
error. A module with neither is scripts-only.

**How it runs.** The framework's `test` first builds its `.m` modules, copies
them up and aggregates `share/` (only when it has `.tst` modules, so a
framework without them behaves exactly as before), then enters each `.tst`
module. `TEST=<name>` matches a test program or a script name. The scripts
get `PATH` = the module's test directory, its framework's `bin`, the
workspace's `bin` and each `PARENT_WS`'s `bin`, and `BMK_SHAREDIR` = the
matching `share` directories, colon-separated in the same order. Kyua passes
the environment through unchanged.

## `make test` — one target, not two

`test` first brings the module's own build up to date (it depends on
`all`), then builds the test programs: without that, a library source
edit followed by only `bmake test` ran the tests against the previous
library (`test-rebuilds-module-library-req`; found in real use — a test
written to fail on the old code passed).

There is no separate `test-all` target. `test` always builds, runs, and
writes JUnit XML (`build/<KEY>/runs/<RUN_ID>/test-results.xml`, plus a
`runs/latest` copy — `40-cli-reference.md`); `REPORT=yes` additionally
builds the HTML report alongside it (`.../test-report-html/`) —
generated on failure too, not only on success
(`REQ-unit-test-full-suite-html-report-req`). `test` exits non-zero if
any test failed, whether or not `REPORT=yes` was given.

| Scope | Behavior |
|---|---|
| module | Build + run this module's declared (or `TEST=`-selected) tests |
| framework | Recurses into every module (or just the one declaring `TEST=<name>`, pre-filtered so a non-matching module is silently skipped, not an error); a module with no tests declared just echoes and exits 0 |
| workspace | Same recursion (or just `FW=<name>`), **plus**, with `REPORT=yes`, a workspace-level dashboard — see below (`REQ-test-workspace-aggregation-req`) |

One module's test failure does not stop every other module from still
being run — `FAIL_FAST=yes` opts into stopping the recursive run at the
first failure instead (`40-cli-reference.md`).

## `TEST=` and `FW=`: running just one test

```
bmake test TEST=hello_test              # module or framework level
bmake test FW=Hello TEST=hello_test     # workspace level, narrowed further
```

`TEST=<name>` narrows a run to one declared test. At module level, a
name that matches none of `TESTS_CXX=`/`TESTS_C=`/`TESTS_SH=` fails
loudly (`.error`, most likely a typo) rather than silently doing
nothing. At framework/workspace level, `TEST=` is pre-filtered before
recursing: each module's own declared test names are queried first (a
plain `-V` query, same pattern as `mk.lib.mk`'s `PREREQS=` lookup), and
only a matching module is actually invoked — so requesting a test that
doesn't exist ANYWHERE in scope produces no output and no error, not N
copies of the module-level error. `FW=<name>` at workspace level further
narrows recursion to one framework before that module-level filtering
happens (`REQ-test-single-selection-req`).

## Workspace-wide runs and the dashboard

`bmake test REPORT=yes` from the workspace root builds and runs every
declared test across every framework and module (or the `FW=`/`TEST=`-
narrowed subset), then generates one dashboard —
`test-report/<RUN_ID>/<KEY>/index.html` at the workspace root (`<KEY>`
being the same compound target key as `build/<KEY>/`), with
`test-report/latest/<KEY>/` always kept as a copy of the newest one for
that key — listing every module that produced a report, its framework,
a PASS/FAIL status (with a failure count, derived from `<failure>`/
`<error>` tags in that module's own JUnit XML — kyua uses `<error>`
specifically for a crashed/aborted case, e.g. a sanitizer abort, not
`<failure>`), and links to both that module's own HTML report and its
JUnit XML. Built by walking for `test-report-html/` directories under
that same `RUN_ID` after the run completes, rather than statically
re-deriving which modules declare tests — since a no-tests module never
creates that directory (and a `TEST=`/`FW=`-filtered run never touches
modules outside its scope), existence is sufficient, and the scan itself
respects the same `FW=`/`TEST=`/`RUN_ID` scoping as the run, so a
narrowed or later run's dashboard doesn't surface stale results from a
different run or a module it didn't touch this time. The `<KEY>`
segment matters specifically because two target keys (e.g.
`TOOLCHAIN=llvm` and `TOOLCHAIN=gcc`) built under the same `RUN_ID` to
correlate them as one CI pass must not overwrite each other's dashboard
(`REQ-test-workspace-aggregation-req`, `REQ-run-history-not-overwritten-req`).

`TEST_REPORT_DIR ?= test-report` is overridable — e.g. giving a
periodic sanitizing run its own `TEST_REPORT_DIR=test-report-sanitized`
keeps it from overwriting the regular run's dashboard. See
`40-cli-reference.md` for where build/test logs live and how this
composes with an external CI/integration-manager process.

## Toolchain notes

MacPorts' `atf-c++` 0.21 headers use `std::auto_ptr`, which libc++ drops
under C++17 mode (clang's default); gcc/libstdc++ keeps it deprecated-
but-present at the same standard level. `mk.test.mk` compensates
unconditionally with `-D_LIBCPP_ENABLE_CXX17_REMOVED_AUTO_PTR` (a
libc++-recognized back-compat macro, no-op under libstdc++) — a
documented, accepted toolchain-packaging gap, not a Bmake It bug.

## Sanitizer interaction

`SANITIZE=` (`40-cli-reference.md`) composes with `test` at every scope
via the shared `CFLAGS`/`CXXFLAGS`/`LDFLAGS` — no test-specific wiring
needed. A sanitizer-caught test aborts (SIGABRT)
rather than returning a normal pass/fail, which kyua reports as
"broken"/`<error>` rather than `<failure>` — the workspace dashboard
above treats both the same way (any non-clean result). Verified against
a real ASan heap-buffer-overflow (library module) and a real UBSan
signed-integer-overflow (program module) in the same run.

**Rebuild before testing**: `test` does not depend on `all` and never
rebuilds the module's own library/executable itself -- only the test
binary is recompiled fresh each run. Running `bmake test SANITIZE=address`
against a library that was last built *without* `SANITIZE=` links the
test against an unsanitized library and won't catch anything. Rebuild
with the same `SANITIZE=` first (`bmake all SANITIZE=address`).

That rebuild step is now reliable rather than a trap: plain `make`'s
staleness model is purely timestamp-based and has no native notion of
"built with different flags," but `all` now fingerprints
`CC`/`CXX`/`CFLAGS`/`CXXFLAGS`/`LDFLAGS`/`SANITIZE`/`TOOLCHAIN` per
module (`INPUTS_HASH_EXTRA=` open for other mechanisms to extend) and
forces exactly the affected objects to recompile whenever that
fingerprint changes -- confirmed with a real heap-buffer-overflow
fixture, split across two compilation units so `-O2` (bmake's own
`sys.mk` default) can't prove the overflowing store dead: silent and
uncaught under a plain build, a genuine `AddressSanitizer:
heap-buffer-overflow` abort after `SANITIZE=address`, using the exact
same already-built objects a naive rebuild would have silently reused
before (`REQ-inputs-hash-rebuild-req`). The remaining caveat is
narrower than before: `test:` still won't run `all:` for you, so the
explicit `bmake all SANITIZE=address` step is still required -- it just
no longer silently no-ops when you do remember to run it.
