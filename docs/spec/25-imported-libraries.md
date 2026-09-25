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

## Link transitivity

A module's `LIBS=<name>` automatically pulls in `<name>`'s own
transitive link dependencies, not just `-l<name>` itself, uniformly for
compiled and imported static libraries (`REQ-import-link-transitivity-
req`). Every library module — whether it compiles `SRCS` or resolves
via `IMPORT=` — writes its own flattened direct link deps to
`lib<LIB>.linkdeps`, alongside `lib<LIB>.*` itself (so it travels
through the existing copy-up mechanism and is found via the existing
`_LIB_SEARCH_DIRS`, no new search path). A consumer's `LIBS=<name>` loop
reads and appends `<name>`'s own `.linkdeps` content in addition to
`-l<name>`.

- **Compiled library**: its `.linkdeps` content is its own `LIBS=`,
  each already expanded through *their* own `.linkdeps` files —
  recursive by construction, since build order already guarantees a
  dependency is fully built (`.linkdeps` included) before anything that
  depends on it starts. A three-level, purely-compiled chain (app →
  libb → libc, where `app.m` declares only `LIBS=b`) proves this: the
  final link line includes `-lc` with no `LIBS=c` anywhere in `app.m`'s
  own makefile.
- **Imported library**: its `.linkdeps` content is `pkg-config --libs
  --static`'s own output (already the correct transitive set for that
  package, including `Libs.private`) minus its own self `-l<LIB>`/
  `-L<owndir>` tokens. A real `Libs.private` entry (the case a project
  like GDAL privately linking PROJ actually hits) was verified
  end-to-end: the private dependency's symbol resolves and runs
  correctly in a consumer that never mentions it.
- This changes existing behavior for **every** module's `LIBS=`, not
  just `IMPORT=` ones — a compiled static library's own transitive deps
  now follow it automatically where they previously required every
  consumer to list them by hand. In scope deliberately: the objective is
  that imported and compiled libraries be indistinguishable to a
  consumer, and that has to hold for linking too, not just headers.
- No found-guard against the same library name resolving in more than
  one `_LIB_SEARCH_DIRS` entry (a shadowing scenario) — duplicate
  `-l`/`-L` flags are harmless to a linker, an accepted simplification.

## Resolution caching

A second build with nothing relevant changed does not re-invoke
`pkg-config` at all (`REQ-import-resolution-cache-req`) — a real,
separate question from item 4's own staging cache (which already
skipped redundant *file copies*, not the resolution call itself). A
per-module fingerprint (`IMPORT=`, `PKG_CONFIG_PATH`,
`_PKG_CONFIG_EXTRA_DIRS`, `TARGET`/`TARGET_ARCH`) is checked against a
stored cache before calling `pkg-config`; a match reads the previously
resolved values back, a mismatch (or no cache) resolves for real and
writes the new cache. Verified with a genuine call-counting `pkg-config`
stub, not just by inspecting the cache file: the first build makes real
calls, an unchanged second build makes zero additional calls, and a
changed `PKG_CONFIG_PATH` triggers real re-resolution again.

This does **not** detect a package silently upgraded in place with no
env/hook/`PKG_CONFIG_PATH` change (the fingerprint doesn't cover the
resolved `.pc` file's own content or mtime — locating it at all would
require the very `pkg-config` call being skipped, a chicken-and-egg
problem a simple fingerprint avoids by not trying). A real bug was
found and fixed while building this: the cache's read-back path
originally set the resolved values unconditionally, even for a cached
*miss* — turning a correctly-undefined resolution (which should fall
through to probing, then the final `.error`) into defined-but-empty,
silently skipping both. Caught by the existing precedence test (case
48), not the new caching test itself, since `IMPORT=` modules are
parsed twice per `bmake` invocation (once for `all`, once for
`copy-up`) and the second parse hit the cache the first had just
written for a step in the middle of a multi-step precedence sequence.

## `PUBLIC_HEADERS_SYSTEM=yes` applies here too

D3 (`-isystem` for a framework's public headers, see
`50-makefile-macros.md`) is framework-level and doesn't care whether
the modules inside compile or `IMPORT=` — an externals framework whose
modules are all `IMPORT=`-resolved can set `PUBLIC_HEADERS_SYSTEM=yes`
exactly like any other framework wrapping third-party code, and gets
the same treatment for its consumers.

## What this chapter does not yet cover

- **Header transitivity** — explicitly rejected: if framework A has
  `PREREQS=B` and B's public headers `#include` C's, A must list
  `PREREQS=C` itself. No transitive `PREREQS=` resolution.
- **`install`/packaging** rewriting dylib install names for imported
  shared libraries, or an opt-out from staging a system library into a
  packaging tree — explicitly parked, not decided: to be tackled once
  the cross-platform test harness itself is dealt with seriously, not
  before. Also moot today in a different sense: there is no
  `distrib`/packaging target implemented at all yet
  (`pkg`/`deb`/`rpm`/`msi` remain structural placeholders per
  `README.md`'s own Status section).
