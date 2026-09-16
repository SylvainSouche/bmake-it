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

## `make test` — one target, not two

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
with the same `SANITIZE=` first (`bmake all SANITIZE=address`) --
plain `make` doesn't detect a flags-only change as a reason to
recompile, so a stale `build/` from an earlier, differently-flagged
build is a real trap, not just a sanitizer-specific one.
