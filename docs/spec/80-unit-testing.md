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

## `make` targets

| Target | Scope | Behavior |
|---|---|---|
| `test` | module | Build + run this module's declared tests; always writes a JUnit XML report (`build/<KEY>/test-results.xml`); exits non-zero if any test failed |
| `test-all` | module | Same, plus a full HTML report (`build/<KEY>/test-report-html/index.html`) — generated on failure too, not only on success (`REQ-unit-test-full-suite-html-report-req`) |
| `test` | framework, workspace | Recurses into every module (workspace: via every framework); a module with no tests declared just echoes and exits 0 |
| `test-all` | framework | Same recursion, `test-all` at each module |
| `test-all` | workspace | Same recursion, **plus** a workspace-level dashboard — see below (`REQ-test-workspace-aggregation-req`) |

Both module-level targets always produce their report regardless of
pass/fail — a failure is exactly when the report matters most. At every
scope, one module's failure doesn't stop the others from running (each
recursive `${MAKE} -C ... test[-all]` is `|| true`'d).

## Workspace-wide runs and the dashboard

`bmake test-all` from the workspace root builds and runs every declared
test across every framework and module, then generates one dashboard —
`test-report/index.html` at the workspace root — listing every module
that produced a report, its framework, a PASS/FAIL status (with a
failure count, derived from `<failure>`/`<error>` tags in that module's
own JUnit XML — kyua uses `<error>` specifically for a crashed/aborted
case, e.g. a sanitizer abort, not `<failure>`), and links to both that
module's own HTML report and its JUnit XML. Built by walking for
`test-report-html/` directories after the recursive run completes,
rather than statically re-deriving which modules declare tests — since a
no-tests module's `test-all` never creates that directory, existence is
sufficient (`REQ-test-workspace-aggregation-req`).

## Toolchain notes

MacPorts' `atf-c++` 0.21 headers use `std::auto_ptr`, which libc++ drops
under C++17 mode (clang's default); gcc/libstdc++ keeps it deprecated-
but-present at the same standard level. `mk.test.mk` compensates
unconditionally with `-D_LIBCPP_ENABLE_CXX17_REMOVED_AUTO_PTR` (a
libc++-recognized back-compat macro, no-op under libstdc++) — a
documented, accepted toolchain-packaging gap, not a Bmake It bug.

## Sanitizer interaction

`SANITIZE=` (`40-cli-reference.md`) composes with `test`/`test-all` at
every scope via the shared `CFLAGS`/`CXXFLAGS`/`LDFLAGS` — no
test-specific wiring needed. A sanitizer-caught test aborts (SIGABRT)
rather than returning a normal pass/fail, which kyua reports as
"broken"/`<error>` rather than `<failure>` — the workspace dashboard
above treats both the same way (any non-clean result). Verified against
a real ASan heap-buffer-overflow (library module) and a real UBSan
signed-integer-overflow (program module) in the same run.
