# Bmake It

A BSD-make-based, cross-platform build system for C/C++ (and lex/yacc),
inspired by Dassault Systèmes RADE/`mkmk` concepts (workspaces, frameworks,
modules, prerequisites) while staying idiomatic to BSD make. Shorthand: `bmk`.

## Layout

```
mk/                      # role makefiles
├── mk.common.mk          # host/target detection, OS_ARCH key, shared defs
├── mk.toolchain.llvm.mk  # LLVM/clang toolchain bundle
├── mk.toolchain.gcc.mk   # GNU gcc toolchain bundle
├── mk.toolchain.msvc.mk  # MSVC toolchain bundle (tier 1, native Windows)
├── mk.vcvarsall.mk       # MSVC environment auto-discovery
├── mk.workspace.mk       # workspace role (PARENT_WS=, framework discovery)
├── mk.framework.mk       # framework role (PREREQS=, module discovery+order)
├── mk.prog.mk            # executable module (PROG=, LIBS=)
├── mk.lib.mk             # library module (LIB=, LIB_SHARED=, INCL=, SHLIB_*)
├── mk.docs.mk            # `bmake docs` — Doxygen generation + tag-file cross-linking
├── mk.test.mk            # `bmake test`/`test-all` — ATF/Kyua unit tests
└── mk.local.mk           # per-level mk/ hook-file cascade (pre.mk/local.mk)
include/                 # bmk_export.h (portable dllexport/dllimport macros)
scripts/                 # gen-mod-order.sh, gen-fw-order.sh, MSVC wrappers
examples/myworkspace/    # worked example (System + Hello frameworks)
tests/                   # script-driven test harness for mk/*.mk itself
docs/
├── spec/                 # design specification (00-overview.md … 80-*.md)
└── manual.tex            # LaTeX package manual
project-model/           # discovery-driven-dev project model (see below)
```

## Quick start

```sh
# Requires: bmake, a C toolchain (clang or gcc), optionally flex/bison
cd examples/myworkspace
bmake                          # build for host OS/arch (e.g. linux-amd64)
bmake TARGET=freebsd TARGET_ARCH=amd64 TOOLCHAIN=gcc   # select target key
bmake clean
bmake install DESTDIR=/tmp/stage PREFIX=/usr/local
```

Run the example binary:

```sh
LD_LIBRARY_PATH=build/linux-amd64/lib ./build/linux-amd64/bin/hello
# → Hello, Bmake It!
```

Generate docs and run unit tests (from a framework or module directory):

```sh
bmake docs      # Doxygen HTML for this framework (or every framework +
                # a workspace landing page, from the workspace root)
bmake test      # build + run this module's TESTS_CXX=/TESTS_C=/TESTS_SH=
                # via ATF/Kyua; JUnit XML report
bmake test-all  # same, plus a full HTML report
```

See `docs/spec/70-documentation-generation.md` and `docs/spec/80-unit-testing.md`.

## Domain model

| Concept    | Role makefile        | Key macros                          |
|------------|-----------------------|-------------------------------------|
| Workspace  | `mk.workspace.mk`    | `PARENT_WS=` (absolute paths)       |
| Framework  | `mk.framework.mk`    | `PREREQS=` (**mandatory**, even empty) |
| Executable | `mk.prog.mk`         | `PROG=`, `LIBS=`                    |
| Library    | `mk.lib.mk`          | `LIB=`, `LIB_SHARED=YES\|NO`, `INCL=`, `SHLIB_MAJOR=` |

- **Module dirs** named `NAME.m`, auto-discovered.
- **Frameworks** auto-discovered via `makefile` containing `PREREQS=`.
- **Header visibility** (3 levels): `fw/include/` (public via PREREQS),
  `fw/local/include/` (all modules of this framework), `module.m/include/`
  (private). Generated headers stay private unless listed in `INCL=`.
- **LIBS=** is link-only; it does not affect header search.
- **Build outputs** under `build/<os>-<arch>[-toolchain]/{bin,lib,share,obj,include}/`.

## Target key

`<os>-<arch>[-<toolchain>][-<abi>]` with defaults omitted (`llvm`, platform
default ABI). Concrete keys include `macos-arm64`, `macos-arm64-gcc`,
`freebsd-amd64`, `freebsd-amd64-gcc`, `win-amd64` (MSVC/Cygwin-gcc tier 1,
mingw-w64 cross-compile tier 2). Host builds also work (e.g. `linux-amd64` on
a Linux host).

## Status

Implements the design described in `docs/spec/`. Known limitations:

- Cross-compilation toolchains are stubs (host compiler used) for most
  non-Windows targets; real path tables for phase-1 targets need filling on
  FreeBSD/macOS hardware.
- Cycle detection reports failure rather than being silent (prototype
  behaviour).
- Packaging targets (`pkg`, `port`, …) and full `share/` overlay testing
  are structural placeholders.
- `.depend` / mkdep-style header dependency tracking not yet wired.

## Methodology

`project-model/` was built with **discovery-driven-dev**, a Claude Code
skill for keeping requirements, decisions, and implementation links in durable
files instead of conversation history. Bmake It was its first real testbed;
link to the skill's own repo to follow once it's published.

### Specs vs. implementation: three layers, one direction of truth

This repo has three places a claim about the build system could live, and
they are not peers:

1. **`project-model/`** is the source of truth. Every requirement (REQ),
   decision (DEC), observation (OBS), and implementation link (IMPL) is a
   machine-checked object — `model.py check --strict` verifies the graph
   is internally consistent (no dangling edges, no tampered frontmatter),
   and `check_impl.py` cross-checks it against the actual code via
   `@impl <IMPL-id>` markers (catching an IMPL claiming code that no
   longer exists, or code with no corresponding model entry).
2. **`mk/*.mk` (and other code)** is the implementation. It either carries
   an `@impl` marker pointing at a real IMPL object, or it doesn't exist
   in the model's eyes yet — `check_impl.py`'s "uncovered leaves" report
   is the honest list of confirmed requirements with no implementation.
3. **`docs/spec/*.md` and `docs/manual.tex`** are a hand-written prose
   *synthesis* of (1), for a human reader who doesn't want to read 300+
   individual model files. Every claim in a `docs/spec/*.md` chapter cites
   the `REQ-`/`CON-`/`NREQ-` alias it comes from — a claim with no
   citation is suspect. This layer is **not** auto-generated and **not**
   authoritative: it is written by hand after a feature lands in (1) and
   (2), which means it can and does lag behind. If `project-model/` and
   `docs/spec/` ever disagree, `project-model/` is right.

Practical discipline: when a feature is implemented and modeled, update
its `docs/spec/*.md` chapter (or add a new one) in the same pass — don't
let the prose synthesis silently drift, the way it did for documentation
generation, local-mk customization, and unit testing before this note was
written.

## License

BSD 3-Clause — see [`LICENSE`](LICENSE).
