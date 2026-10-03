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

**pkg-config details.** Step 3 captures `--cflags`, `--modversion`,
`--variable=libdir` and `--variable=includedir`. The last exists because
pkg-config omits `-I<dir>` for a **system** include directory
(`/usr/include` on Linux), so `--cflags` can be empty for a perfectly
installed package — header staging searches the `-I` dirs and then
`includedir`, never the compile flags, which are unchanged
(`import-system-includedir-fallback-req`; found on Ubuntu with glm and
glfw3). For `--libs`, which flavor depends on what was
actually found at the resolved libdir
(`shared-import-link-flags-fix-req`): a **shared** library (`.so`/
`.dylib`) uses plain `pkg-config --libs` (just this package's own `-L`/
`-l`) — a shared library embeds its own dependency references
(`install_name`/rpath on macOS, `DT_NEEDED` on ELF), resolved by the
dynamic linker at *load* time, not link time, so the full `--static`
transitive closure is unnecessary and, found in real use (importing
`gdal`), actively risky: a `Libs.private:` entry may validly omit its
own `-L` (relying on the *host's* own default linker search path),
which this project's own build doesn't necessarily share, producing
`ld: library 'X' not found` for an entirely unrelated transitive
dependency (`gdal`'s own `lz4`). A **static-only** import (no `.so`/
`.dylib` found) uses `--libs --static` (`Libs.private`, the transitive
link deps the link-transitivity mechanism below needs — a `.a` carries
no dependency info of its own for the final consumer to resolve at
link time). Extra `.pc` search directories
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
list. Its own success criterion is normally "a `lib<LIB>.*` file exists
at `<prefix>/lib/`" — except under `IMPORT_LIB=none` (below), where it's
"the first `IMPORT_HEADERS=` entry exists under `<prefix>/include/`"
instead, since there is no lib file to probe for.

## Header-only imports (`IMPORT_LIB=none`)

(`header-only-import-req`)

`IMPORT_LIB=none` declares that no `lib<LIB>.{a,so,dylib}` exists
anywhere for this import, by design — a real gap found importing `glm`:
it ships no `.pc` file at all, so step 3 never applies, and step 4's
own lib-file probe only ever found a result because MacPorts' particular
glm package happens to ship an *optional* compiled library — a
genuinely header-only glm install (the common case) would never
resolve. With `IMPORT_LIB=none`, step 4's probe switches to a header
existence check (above), and whatever *did* resolve (env/hook/`pkg:`/
`prefix:`/probing) has its lib-staging suppressed regardless of what
that source might otherwise have reported — reusing `_stage_import:`'s
existing "no resolved library directory" skip (below), not a new
staging path. Since there's no library, a consuming module needs no
`LIBS=` entry for it either — just the ordinary framework-level include
path a `PREREQS=`-visible (or same-framework) module already gets.

This is the half of the original proposal that goes through the full
`IMPORT=` module -- for a header-only dependency a module reaches via
its own ordinary `CFLAGS+=`/`CXXFLAGS+=` instead (no `IMPORT=` module at
all), see `REQUIRES=header:<path>` in `27-prerequisite-software.md`
(`requires-header-form-req`) — a presence check only, no staging.

## Staging

(`REQ-import-staging-req`)

- **Headers**: only the names in `IMPORT_HEADERS=` are copied — never
  the whole resolved include directory, which would leak every
  unrelated package under it and defeat `PREREQS=`-based visibility.
  They land in `<fw>/build/<KEY>/include/`, the same destination
  promoted generated headers already use (`REQ-generated-headers-in-
  build-tree-req`) — a `PREREQS=`-declared consumer already searches
  there. An entry containing a shell glob metacharacter (`*`, `?`,
  `[...]`) stages every match, not just one exact name
  (`import-headers-glob-req`) — found in real use importing `gdal`,
  whose ~150 headers sit loose directly in its includedir with no
  per-package subdirectory to stage wholesale the way a single
  directory name already could; a glob like `IMPORT_HEADERS=gdal_*.h
  ogr_*.h cpl_*.h` covers them without hand-listing each one. A plain,
  glob-free entry behaves exactly as before.
- **Libraries**: `lib<LIB>.{a,so*,dylib}` are copied into the *module's
  own* `build/<KEY>/lib/`, exactly where a compiled library's own
  `ar`/link recipe would have written them — so `LIBS=<lib>` in a
  consumer needs no changes at all.
- **Real files are copied; the resolved prefix's own symlink chain is
  recreated, never copied verbatim.** A shared library's on-disk layout
  is routinely more than one file: an unversioned name a linker's
  `-l<lib>` resolves at *link* time (`libfoo.dylib`, `libfoo.so`), and a
  separately-named, more specific file the runtime loader actually opens
  via the library's own embedded `install_name`/`SONAME` (`libfoo.34.dylib`
  on macOS, `libfoo.so.34` on ELF — note macOS puts the version *before*
  the extension, ELF *after*). The unversioned name is usually a symlink
  to the versioned one. Copying that symlink byte-for-byte (`cp -a`)
  either leaves it dangling (its real target's own name was never staged
  alongside it) or, for an absolute-target symlink as MacPorts/Homebrew
  commonly produce, silently points back into the original host prefix
  instead of the staged, portable build tree — both observed producing a
  library that links but fails to *load* at runtime, against real macOS
  packages (`import-staging-broken-dylib-symlinks-obs`). Staging instead
  resolves every `lib<LIB>.*` entry to its real underlying file (copied
  for real) and recreates each symlinked name it found as a fresh,
  same-directory relative symlink pointing at that file — self-contained
  within the staged tree, matching this project's own established "copy,
  not symlink *across* the build tree" precedent (the `RUN_ID=`/`latest`
  mechanism was deliberately switched from symlinks to real copies
  earlier in this project's history, specifically because Cygwin's
  default symlinks are a text-marker file, not resolvable by a native
  Windows file browser or web server) without losing the version-symlink
  chain a shared library's own link/load model actually needs. When the
  chain ends at a real file in a **different directory** than the import's
  `lib/` (a distro's `libglfw.so -> libglfw.so.3 -> libglfw.so.3.3 ->
  /usr/lib/<triple>/libglfw.so.3.3`, every entry a symlink), that real
  file is copied into the staged `lib/` once under its own name and each
  other name becomes a relative link to it — a name is never linked to
  itself (`staging-symlink-chain-real-file-req`; the old behaviour made
  `libglfw.so.3.3 -> libglfw.so.3.3`, a loop).
- **A compiled static library built with `OPENMP=yes` records the OpenMP
  runtime** (`-fopenmp`, and the runtime's `-L` where mk.common.mk adds one)
  in `lib<LIB>.linkdeps` (`static-lib-openmp-linkdeps-req`). A static
  library carries no dependency information of its own, so a module linking
  it through `LIBS=` and not setting `OPENMP=` itself otherwise failed with
  `undefined ___kmpc_fork_call` (lasviewer round 8).
- **`IMPORT_LIB=none` prints no "no resolved library directory" message**
  (`import-lib-none-quiet-req`): that boundary message is for the env/hook
  `CFLAGS`+`LIBS` mode, where it is real; a header-only import declared that
  there is no library, so it was misleading.
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
  own makefile. Each `-l<name>` carries its resolved `-L<dir>` (link
  time) and, for a shared library, `-Wl,-rpath,<dir>` (run time)
  alongside it, not just the bare name
  (`transitive-linkdeps-missing-l-fix-req`) — found in real use: a
  consumer that doesn't *also* happen to put that directory on its own
  search path some other way (e.g. by listing the same framework in its
  own `PREREQS=`) would otherwise link only by accident, and even then
  couldn't *load* a shared transitive dependency found only this way.
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
  `-l`/`-L` flags are harmless to a linker. They *are*, however, noisy:
  two `LIBS=` entries sharing a common transitive dependency both carry
  it forward, and the final link's own `LDFLAGS` is deduplicated
  (first-occurrence preserved, never reordered — static link order can
  matter) right before use (`duplicate-linkdeps-fix-req`) — found in
  real use as a pure-noise `ignoring duplicate libraries` linker
  warning on every link. The dedup runs **inside the link recipe**, not
  as a parse-time assignment, and only touches `-l*`, `-L*` and
  `-Wl,-rpath,*` tokens (`ldflags-dedup-hook-timing-fix-req`): a
  parse-time version ran before `mk.local.mk`'s `local` phase, so any
  `LDFLAGS +=` from a `local*.mk` post-hook (e.g. `-framework OpenGL`)
  silently never reached the link, and comparing single words split a
  flag+argument pair like `-framework X` or `-Xlinker X`. Every other
  token passes through untouched, repeats included.
- **Each module is entered once, and a second visit is a no-op.**
  Workspace and framework each run `all copy-up` as ONE `make`
  invocation per child (it used to be two processes, the second
  re-parsing the whole makefile chain — `IMPORT=` resolution included —
  only to find nothing to do), and `gen-mod-order.sh` asks for
  `LIBS`/`LIB`/`PROG` in one `bmake -V` run per module instead of three
  (`single-module-visit-req`; a four-module imported framework went from
  ~2.6 s to ~0.9 s before its first module was entered). Within one
  visit: `_stage_import:` is guarded by a fingerprint of
  `IMPORT`/`IMPORT_HEADERS`/`IMPORT_LIB` and the resolved
  source/cflags/libdir, kept in `build/<KEY>/.stage-fp` (under the build
  root so `bmake clean` discards it with the outputs it vouches for);
  an unchanged fingerprint exits silently before any copy or message
  (`import-staging-idempotent-req`), and the `===> imported` line is
  printed from that guarded block only. The same holds for the
  `fetch:` + `SRCS=` path: `_stage_fetch_headers:` is fingerprint-guarded
  (`IMPORT_HEADERS=` plus the extraction fingerprint), and `built
  static/shared/<prog>` is printed by the archive/link recipe itself, not
  by `all:`, so a visit that rebuilt nothing says nothing
  (`repeated-messages-fix-req`). `lib<LIB>.linkdeps` is written
  only when its content differs (`linkdeps-write-idempotent-req`). The
  framework's `build/<KEY>/{bin,lib,share,include}` are created before
  any module is built, on every pass (`framework-dir-creation-ordering-fix-req`):
  `-I<fw>/build/<KEY>/include` is added to CFLAGS by a parse-time
  `exists()` check, and creating the directory only after the modules
  built made a module's CFLAGS differ between the first and second pass,
  which changed the inputs hash and recompiled and re-archived it (the
  new embedded `ar` timestamp then triggered a `copy-up collision`
  warning on a clean build).
- A module's own framework `-L` search path is only added when that
  directory actually exists (`prog-only-framework-ld-warning-fix-req`)
  — a framework holding only a `PROG` (no `LIB` module at all) never
  creates its own `build/<KEY>/lib/`, and an unconditional `-L`
  produced a harmless but noisy `ld: warning: search path ... not
  found` on every single link (found in real use: an app-only,
  Viewer-class framework).

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
