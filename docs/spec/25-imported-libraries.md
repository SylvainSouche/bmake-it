# Bmake It — 25: Imported Libraries

Status: DRAFT, synthesized from confirmed `project-model/req/` objects.
Every claim cites the REQ/DEC alias it comes from.

## Scope and objective

A library module either compiles its own `SRCS`, or imports a prebuilt
library via `IMPORT=`. Either way it produces the same `lib<LIB>.*`
outputs in the same `build/<KEY>/lib/` location, and a consumer sees no
difference at all — `PREREQS=` for headers, `LIBS=<lib>` for linking,
exactly as for a compiled library (`REQ-imported-libraries-are-ordinary-
modules-req`). There is no consumer-side mechanism specific to imported
libraries; switching a module between compiled and `IMPORT=` requires no
change in any consumer.

```makefile
# an ordinary framework, sharable via PARENT_WS= like any other
PREREQS=
.include <mk.framework.mk>
```

```makefile
# an ordinary library module -- imports instead of compiling
LIB=pdalcpp
IMPORT=pkg:pdal
IMPORT_HEADERS=pdal
.include <mk.lib.mk>
```

`LIB_SHARED=` is ignored for an import: whatever `lib<LIB>.{a,so*,dylib}`
files the resolved source actually has are staged, not a choice this
project makes.

## Resolution — a four-step ladder, first match wins

(`REQ-import-resolution-ladder-req`)

| Step | Source | Trigger |
|---|---|---|
| 1 | Environment/CLI | `<LIB:tu>_PREFIX=`, or `<LIB:tu>_CFLAGS=` + `<LIB:tu>_LIBS=` |
| 2 | `mk/` hooks | `IMPORT_PREFIX=`, or `IMPORT_CFLAGS=` + `IMPORT_LIBS=` |
| 3 | `pkg-config` or a literal prefix | `IMPORT=pkg:<name>` or `IMPORT=prefix:<dir>` |
| 4 | Probing | `mk.paths.<os>.mk`'s own `_TOOL_PREFIXES`, searched for `lib<LIB>.*` |

An unresolved import is a parse-time `.error` naming the module, the
target key, and every source tried, with an install hint pointing at
`README.md`'s Prerequisites section.

`IMPORT=` syntax: `pkg:<name>` (pkg-config), `prefix:<dir>` (direct, no
pkg-config involved), or empty (only steps 1–2 can resolve it).

**pkg-config details.** Step 3 captures `--cflags`, `--libs --static`
(not plain `--libs` — `--static` also pulls in `Libs.private`, the
transitive link deps a future link-transitivity mechanism needs),
`--modversion`, and `--variable=libdir`. Extra `.pc` search directories
come from `_PKG_CONFIG_EXTRA_DIRS` (`mk.paths.<os>.mk`'s own extension
point, mirroring `_TOOL_PREFIXES`; empty by default — no real per-OS
entry is populated in this repo, since a concrete need such as
MacPorts' `proj9`-via-GDAL path is specific to whatever project
consumes this mechanism, not a generic Bmake It default). They are
**added** to the caller's own inherited `PKG_CONFIG_PATH`, never
replacing it — a real install found via pkg-config's own built-in
default search paths (e.g. MacPorts pkg-config already defaulting to
`/opt/local/lib/pkgconfig`) keeps working with zero configuration.

**Cross-compilation.** When `TARGET` differs from the native host,
`PKG_CONFIG_SYSROOT_DIR`/`PKG_CONFIG_LIBDIR` are set from the same
`BMK_<OS>_SYSROOT=` variable `mk.toolchain.llvm.mk`'s own cross branches
already require, and `PKG_CONFIG_PATH` is left unset so host `.pc`
files are never read. Implemented per spec, **not empirically verified
end-to-end** — no foreign sysroot with real `.pc` files was available to
test against; cross-compilation itself is out of scope this round
beyond keeping this behavior correct (matches the project's existing
cross-compilation status — stubs for most non-Windows targets).

**Step 4 (probing)** derives candidate prefixes from `_TOOL_PREFIXES:H`
(the dirname of each already-defined `bin/` entry), not a second prefix
list.

## Staging

(`REQ-import-staging-req`)

- **Headers**: only the names in `IMPORT_HEADERS=` are copied — never
  the whole resolved include directory, which would leak every
  unrelated package under it and defeat `PREREQS=`-based visibility.
  They land in `<fw>/build/<KEY>/include/`, the same destination
  promoted generated headers already use (`REQ-generated-headers-in-
  build-tree-req`) — a `PREREQS=`-declared consumer already searches
  there.
- **Libraries**: `lib<LIB>.{a,so*,dylib}` are copied into the *module's
  own* `build/<KEY>/lib/`, exactly where a compiled library's own
  `ar`/link recipe would have written them — so `LIBS=<lib>` in a
  consumer needs no changes at all.
- **Copy, not symlink** — matches this project's own established
  precedent (the `RUN_ID=`/`latest` mechanism was deliberately switched
  from symlinks to real copies earlier in this project's history,
  specifically because Cygwin's default symlinks are a text-marker
  file, not resolvable by a native Windows file browser or web server).
- **Re-staging** is driven by the existing inputs-hash mechanism
  (`REQ-inputs-hash-rebuild-req`): the resolved source, `IMPORT_CFLAGS`,
  and `IMPORT_LIBS` are folded into `INPUTS_HASH_EXTRA=`, so a changed
  env override, hook value, or a different resolution result re-stages
  the same way a changed `SANITIZE=` triggers recompilation — no
  separate cache-invalidation mechanism needed.
- When step 1 or 2 resolves via `<LIB>_CFLAGS`/`<LIB>_LIBS` (no known
  library *directory*, only opaque flags), library-file staging is
  skipped with a clear message rather than guessed at — a consumer
  relying on plain `LIBS=<lib>` needs `_PREFIX`-style resolution
  instead. A documented boundary, not a silent gap.

## Per-architecture hooks (a prerequisite this chapter needed)

`mk.local.mk`'s hook cascade gained a fourth conventional filename,
`<phase>.${TARGET}_${TARGET_ARCH}.mk` (checked after
`<phase>.${TARGET}.mk`), so an external prefix that differs by
architecture on the same OS — Homebrew's `/opt/homebrew` on arm64 vs
`/usr/local` on amd64, or a cross sysroot — can be expressed
(`REQ-local-mk-arch-variant-req`). See `50-makefile-macros.md`.

## What this chapter does not yet cover

- **Link transitivity** (a static library's own `LIBS=`/`Libs.private`
  automatically following it into a consumer) — a separate mechanism,
  applying uniformly to compiled and imported libraries alike, tracked
  as its own follow-on work.
- **Header transitivity** — explicitly rejected: if framework A has
  `PREREQS=B` and B's public headers `#include` C's, A must list
  `PREREQS=C` itself. No transitive `PREREQS=` resolution.
- **Re-resolution caching** — `IMPORT=`'s resolution (including a
  `pkg-config` invocation) re-runs on every `bmake` invocation, since it
  happens at parse time; only *staging* (the actual file copies) is
  skipped when nothing changed. A persistent resolution cache (skip
  even the `pkg-config` call when the inputs are provably unchanged)
  is a known, deferred enhancement, not a correctness gap — `pkg-config`
  queries are cheap, local commands.
- **`-isystem`** for imported (or vendored) public headers — undecided.
- **`install`/packaging** rewriting dylib install names for imported
  shared libraries, or an opt-out from staging a system library into a
  packaging tree — undecided; also moot today in a different sense:
  there is no `distrib`/packaging target implemented at all yet
  (`pkg`/`deb`/`rpm`/`msi` remain structural placeholders per
  `README.md`'s own Status section).
