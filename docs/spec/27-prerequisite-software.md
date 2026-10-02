# Bmake It — 27: Prerequisite Software (`REQUIRES=`)

Status: Implemented (`mk/mk.common.mk`) and covered by the test harness
(`tests/cases/66-requires-prereq-software`, `77-requires-header-form`, `82-requires-header-prefix`).
Every claim cites the REQ/DEC alias it comes from.

## Scope and objective

`IMPORT=`/`fetch:`/`fetch-bin:`/`FETCH_BUILD=` (`25-imported-libraries.md`,
`26-fetched-external-sources.md`) all *acquire* a library on Bmake It's
behalf — resolved via pkg-config, fetched as a distfile, built by a
delegated build system. Real projects also depend on software Bmake It
has no business acquiring: system-level libraries and tools another
fetched project's own build already knows how to find (PROJ, GEOS,
SQLite, libcurl, ...) or a build-host tool Bmake It itself doesn't
invoke directly (an SDK, a code generator). Without a way to declare
those, a missing one surfaces only once something else's build reaches
it — possibly minutes into a `FETCH_BUILD=cmake` configure, with a
message that has nothing to do with Bmake It.

`REQUIRES=` closes that gap with a single, deliberately small
mechanism (`requires-software-prereq-req`): declare what a module needs
already installed, check it, and error cleanly if it's missing —
nothing more. No Find-module system, no per-package version
constraints, no per-platform install-command database, no target-based
dependency graph — "a la cmake, but not with all that plumbing, just
check or error" (the user's own words, from investigating a `lasviewer`
project built against GLFW/GDAL/PDAL/Dear ImGui, where some
dependencies fit `fetch:`/`fetch-bin:`/`FETCH_BUILD=` cleanly and
others were just prerequisites that had to already be on the host
(`lasviewer-prereq-software-gap-obs`)).

## Declaring a requirement

```makefile
PROG=lasviewer
REQUIRES=proj sqlite3 cmake
LIBS=gdal pdal glfw imgui
.include <mk.prog.mk>
```

`REQUIRES=<name> [<name> ...]` works on any module — `mk.prog.mk` and
`mk.lib.mk` both (`mk.common.mk` is shared by every role). Each `<name>`
is checked two ways, in order:

1. **`pkg-config --exists <name>`** — the usual case for a library
   (`proj`, `sqlite3`, ...), reusing the same tool `IMPORT=pkg:` already
   depends on.
2. **`command -v <name>`** — a fallback for a CLI-tool-style
   prerequisite pkg-config has no `.pc` file for (`cmake`, `ogr2ogr`,
   a code generator, ...).

Whichever succeeds first wins; if neither does, the module fails to
parse with a `.error` naming the module and exactly which `REQUIRES=`
entry couldn't be found:

```
REQUIRES=proj: not found via pkg-config or on PATH -- install it via
your host's package manager (see README.md Prerequisites) before
building
```

## Header-only prerequisites (`header:<path>`, `requires-header-form-req`)

Neither check above fits a header-only library with no `.pc` file at
all: `glm` on a distro that ships no optional compiled library has
nothing for `pkg-config --exists` to find, and it's not a CLI tool
`command -v` can locate either (`lasviewer-third-round-issues-obs`,
issue 5 — the header-only-import half of the same report implemented
`IMPORT_LIB=none`, see `25-imported-libraries.md`).

A `REQUIRES=` entry whose name starts with `header:` is checked a third
way instead:

```makefile
PROG=app
REQUIRES=header:glm/glm.hpp
CXXFLAGS+=-I/opt/local/include
.include <mk.prog.mk>
```

`<path>` (everything after the first `:`) is checked by preprocessing a
trivial translation unit that `#include`s it — never compiled, so the
header's actual C-vs-C++ content is never parsed, only located. Tried
twice, in order:

1. `CC` with the current `CFLAGS`, in C mode.
2. If that fails, `CXX` with the current `CXXFLAGS`, in C++ mode.

Two separate attempts, not one merged pass: a C++-only header's `-I` is
commonly carried on `CXXFLAGS` alongside a real `-std=c++..` flag, which
the compiler rejects outright when forced into C mode. "Current" means
as `CFLAGS`/`CXXFLAGS` stand when `mk/mk.requires.mk` runs — the
module's own makefile (a `CFLAGS+=`/`CXXFLAGS+=` placed *before*
`.include <mk.prog.mk>`/`<mk.lib.mk>` counts), `mk.common.mk`'s
`SANITIZE=`/`OPENMP=` contributions, and any `pre` hook, but not the
later `local` post-hook phase.

If neither attempt finds it, `<prefix>/include/<path>` is tried for every
prefix the `IMPORT_LIB=none` step-4 probe uses (`_TOOL_PREFIXES` with the
trailing `bin/` stripped — `/opt/local`, `/opt/homebrew`, ... on macOS),
so a header installed under a package manager's prefix the compiler
doesn't search by default is found the same way the import finds it
(`requires-header-prefix-probe-req`; found in real use with MacPorts and
glm). This is a presence check only — it adds no `-I`, so a module that
`#include`s the header directly, with no `IMPORT=`, still needs its own.

The check runs from `mk/mk.requires.mk`, included after the `pre` hook
phase, so a `pre` hook's `CFLAGS+=-I...` or `_TOOL_PREFIXES` override is
seen too (only the `local` post-hook phase comes later).

A missing header fails to parse the same way a missing name does, with
its own message naming the path and everything tried, not just the bare
entry:

```
REQUIRES=header:glm/glm.hpp: header glm/glm.hpp not found -- tried
<cc>/<cxx> with the current CFLAGS/CXXFLAGS, and <prefix>/include for:
/opt/local /opt/homebrew ... -- add its include directory to CFLAGS or
CXXFLAGS or install the providing package (see README.md
Prerequisites) before building
```

A plain-name entry and a `header:` entry compose freely in the same
`REQUIRES=` list (`REQUIRES=header:glm/glm.hpp sqlite3 cmake`).

## When the check runs

Parse time, same failure style already used for `CC`/`CXX` resolution
(`mk.toolchain.llvm.mk`) and `IMPORT=pkg:` resolution — before any real
build work starts, not after. Skipped for `clean`, `help`, and a `-V`
query (the same guard `mk.toolchain.llvm.mk`/`mk.toolchain.msvc.mk`
already use for their own parse-time failures): a missing prerequisite
must never block cleaning a module or asking for help.

## What `REQUIRES=` does *not* do

- **Does not stage anything.** No headers, no libraries, no
  `_stage_import:`-style copy into the build tree. The module's own
  `LIBS=`/`CFLAGS+=`/`FETCH_BUILD_CMD=` is still responsible for
  actually finding and using the prerequisite — `REQUIRES=` only
  guarantees it's there before that happens.
- **Does not resolve a cross-compiled target's own sysroot.** The check
  runs against the *host's* own `pkg-config`/`PATH`, the same as
  `IMPORT=pkg:`'s own non-cross-aware fallback path. For a genuinely
  cross-compiled build, "is this installed on the build host" is often
  the wrong question — out of scope here, matching this project's
  already-deferred cross-sysroot package resolution story.
- **Does not version-check.** `pkg-config --exists <name>` succeeds
  regardless of version; there is no `REQUIRES=proj>=7` syntax.
- **Does not know how to install anything.** The error names what's
  missing; it points at this project's own README Prerequisites section
  for how to install things generally, not a per-package command.

## Testing

`tests/cases/66-requires-prereq-software`: a fake, self-contained
pkg-config package (`.pc` file only, no real system package) proves the
pkg-config path; a fake shell-script "tool" placed on `PATH` proves the
`command -v` fallback; a third, genuinely nonexistent name proves the
failure names the right module and entry, and that it happens *before*
any compile is attempted (no object file ever gets built).

`tests/cases/77-requires-header-form`: a fake, templated/namespaced
header (not plain C, to prove the C-vs-C++ dispatch) is found via
`CXXFLAGS`, then via `CFLAGS` alone, each building successfully and
composing with a plain-name `REQUIRES=` entry in the same list; a
missing `-I` and a genuinely nonexistent header path each fail to parse
with their own distinct `header:<path>: header ... not found` message,
before any compile is attempted.

`tests/cases/82-requires-header-prefix`: a header that exists only under a
fake tool prefix the compiler doesn't search (the prefix list is
overridden from a `pre` hook) passes `REQUIRES=header:`; a genuinely
absent one still fails, naming the prefixes tried.
