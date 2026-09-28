# Bmake It — 27: Prerequisite Software (`REQUIRES=`)

Status: Implemented (`mk/mk.common.mk`) and covered by the test harness
(`tests/cases/66-requires-prereq-software`). Every claim cites the
REQ/DEC alias it comes from.

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
