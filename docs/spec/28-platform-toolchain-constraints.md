# Bmake It — 28: Platform and Toolchain Constraints (`PLATFORMS=`, `TOOLCHAINS=`)

Status: **specified, not yet implemented.** Decided in design discussion
2026-10-03 (`platform-toolchain-constraints-dec`).

## Scope and objective

Some modules only make sense on some platforms, or are documented as not
working with some toolchain (a library that miscompiles under gcc, a
Windows-only DLL, a desktop-GL program with no business on a headless
host). Without a declaration, such a module fails the build — or worse,
builds and misbehaves. Two distinct intents have to be expressible:

- **"Not built here"** — this module is simply not part of this
  configuration. Skip it, say so in one line, and carry on.
- **"Must not be built here"** — choosing this combination is a mistake.
  Stop, with an optional explanation.

Dassault Systèmes' mkmk does this with an OS section and a `BUILD=NO`
line inside each OS-specific block. That means editing a second file for
every exclusion, so it is deliberately not replicated here.

## Declaring a constraint

One list macro per axis, set in the module's (or framework's) own
makefile, before the `.include`:

```makefile
PLATFORMS=macos linux              # only these; skipped quietly elsewhere
PLATFORMS=-aix -windows            # everything except these; skipped quietly
PLATFORMS=!macos                   # only macos; an ERROR on any other platform
PLATFORMS=!-linux_arm64            # excluded on linux_arm64, loudly (error)
TOOLCHAINS=-gcc                    # not built with gcc; skipped quietly
TOOLCHAINS=!-gcc                   # building with gcc is an error
REASON.gcc=miscompiles the raster kernels, use TOOLCHAIN=llvm
```

An entry is `[!][-]name`:

| Form | Meaning |
|---|---|
| `name` | positive: **only** these; any other target is skipped quietly |
| `-name` | negative: **not** these; skipped quietly |
| `!name` | positive and **loud**: only these, anything else is an error |
| `!-name` | negative and **loud**: excluded, and choosing it is an error |

Both macros default to "everything". `PLATFORMS=` names an OS (`macos`,
which matches every architecture of it) or one architecture of it
(`macos_arm64`) — spelled with an underscore, as in `share/<os>_<arch>/`
and `local.<os>_<arch>.mk`, not with the build key's hyphen.
`TOOLCHAINS=` names a toolchain as in `mk.toolchain.<name>.mk` (`llvm`,
`gcc`, `msvc`).

## What a valid list looks like

Positive entries ("only these") and negative entries ("not these") do not
mix — except that a negative entry may sit beside positive ones when it
is a **subset** of one of them (`platform-list-validity-req`):

```makefile
PLATFORMS=linux -linux_arm64       # valid: linux_arm64 is part of linux
PLATFORMS=linux macos -linux_arm64 # valid
PLATFORMS=-aix -windows            # valid: negatives only
PLATFORMS=macos -linux             # ERROR: -linux is outside "only macos", redundant
PLATFORMS=linux -linux             # ERROR: removes everything
PLATFORMS=linux_arm64 -linux       # ERROR: -linux is wider than linux_arm64
TOOLCHAINS=llvm -gcc               # ERROR: toolchains have no hierarchy, so no mixing
```

An `os_arch` entry is a subset of its `os`; toolchain names have no such
relation, so a `TOOLCHAINS=` list is all positive or all negative. The
`!` modifier does not change validity. An invalid list is always an
**error** — never a skip — and names the offending entry, so a mistake
in the declaration cannot silently change what is built.

## How a target is evaluated

For the selected target and toolchain, entries are checked in this order
and the first that applies decides
(`platform-constraint-evaluation-req`):

1. a loud negative (`!-x`) that matches — **error**;
2. a quiet negative (`-x`) that matches — **skip**;
3. if there are positive entries and none matches — **skip**, or **error**
   when any positive entry is loud (loud wins);
4. otherwise the module is built.

A more specific entry beats a more general one: `linux -linux_arm64`
builds on every Linux architecture but `linux_arm64`. Both axes are
evaluated, and an error on either wins over a skip on the other.

## Skip versus error

- **Skip** prints one informational line —
  `===> module libfoo.m skipped: PLATFORMS excludes linux_arm64` — and
  exits 0. It is not a warning: the list is the author's declared intent.
  The module's tests are skipped with it.
- **Error** stops the build, with a line naming the entry and the
  selected platform or toolchain.
- An optional **`REASON.<entry>=text`** — a per-name variable, the entry
  spelled as in the list — is appended to either line
  (`constraint-reason-message-req`). Without it a generic message is
  used.

The difference: `PLATFORMS=`/`TOOLCHAINS=` without `!` say where a module
*is part of the build*; with `!` they say that choosing the excluded
combination is a mistake that should stop the build.

## Open (`platform-constraint-open-points-cand`)

- **Dependents of an excluded module.** A module that depends on one
  excluded here and is not itself excluded is an inconsistent declaration.
  Proposed: an error naming both (`Geo needs GIS, which is not built on
  linux_arm64; give Geo the same PLATFORMS=`) — unlike a *failed*
  prerequisite, which cascades as a skip, because a failure is an accident
  and an exclusion is something the author wrote.
- Whether a framework-level `PLATFORMS=` is inherited by its modules.
- Whether `PARENT_WS` workspaces' lists apply.
- Whether the build key's toolchain suffix or the ABI may appear in a
  platform entry.
