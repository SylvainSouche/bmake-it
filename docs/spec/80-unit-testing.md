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
`tests/<name>.c` (atf-c), `tests/<name>.sh` (atf-sh). Compiled tests link
against `atf-c++`/`atf-c` (via `pkg-config`) plus the module's own build
output — a `TESTS_CXX` case implicitly gets the module's own library on
its link line, no separate `LIBS=` entry needed for that.

All three kinds are registered in a generated `Kyuafile` and run via
`kyua test`, agnostic to which kind produced the pass/fail
(`REQ-unit-test-feature-for-built-software-req`).

## `make` targets

| Target | Behavior |
|---|---|
| `test` | Build + run this module's declared tests; always writes a JUnit XML report (`build/<KEY>/test-results.xml`); exits non-zero if any test failed |
| `test-all` | Same, plus a full HTML report (`build/<KEY>/test-report-html/index.html`) — generated on failure too, not only on success (`REQ-unit-test-full-suite-html-report-req`) |

Both targets always produce their report regardless of pass/fail — a
failure is exactly when the report matters most.

## Toolchain notes

MacPorts' `atf-c++` 0.21 headers use `std::auto_ptr`, which libc++ drops
under C++17 mode (clang's default); gcc/libstdc++ keeps it deprecated-
but-present at the same standard level. `mk.test.mk` compensates
unconditionally with `-D_LIBCPP_ENABLE_CXX17_REMOVED_AUTO_PTR` (a
libc++-recognized back-compat macro, no-op under libstdc++) — a
documented, accepted toolchain-packaging gap, not a Bmake It bug.
