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
└── mk.lib.mk             # library module (LIB=, LIB_SHARED=, INCL=, SHLIB_*)
include/                 # bmk_export.h (portable dllexport/dllimport macros)
scripts/                 # gen-mod-order.sh, gen-fw-order.sh, MSVC wrappers
examples/myworkspace/    # worked example (System + Hello frameworks)
tests/                   # script-driven test harness for mk/*.mk itself
docs/
├── spec/                 # design specification (00-overview.md … 60-*.md)
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

## License

BSD 3-Clause — see [`LICENSE`](LICENSE).
