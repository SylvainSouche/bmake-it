# Bmake It — 26: Fetched External Sources (`IMPORT=fetch:`/`fetch-bin:`)

Status: Implemented (`mk/mk.lib.mk`) and covered by the test harness
(`tests/cases/60-fetch-import-source`, `61-fetch-import-checksum-mismatch`,
`62-fetch-import-binary`). Every claim cites the REQ/DEC alias it comes
from.

## Scope and objective

`IMPORT=pkg:`/`prefix:` (`25-imported-libraries.md`) require a library
already installed on the build host. This chapter adds two more
`IMPORT=` kinds that *acquire* one at build time instead — the same
idea real BSD ports/pkgsrc solve, and deliberately modeled on their own
fetch/verify/extract/patch split (confirmed against the FreeBSD
Porter's Handbook, not assumed): a distfile is downloaded from a URL,
checked against a committed checksum, extracted into a scratch work
tree, optionally patched, and then either compiled or staged directly.

The governing rule, stated by the user verbatim: **don't `git` what
isn't yours — just where it is, and how to transform it.** Only the
module's own `makefile`, its `mk/` hooks, a small `distinfo` checksum
file, and any patches are committed. The downloaded distfile and its
extracted work tree never are (`REQ-fetch-cache-never-committed-req`).

This is **not** a copy of `bsd.port.mk` — no code or variable names are
taken from it beyond generic, already-public build-tooling vocabulary
(`distinfo`, `WRKSRC`-style naming). Same stance already taken for
`mk.qt.mk` (`qt-mechanism-original-implementation`): the real mechanism
was researched to understand it correctly, not to adapt its source.

## Two kinds, one ladder

(`REQ-import-resolution-ladder-req`, extended)

```makefile
IMPORT=fetch:<label>        # source: extract, patch, compile as SRCS
IMPORT=fetch-bin:<label>    # prebuilt: extract, stage directly, no compile
```

`<label>` is a human-readable identifier for log/error messages (e.g.
the upstream project's own name) — it does not drive resolution the
way `pkg:`'s `<name>` invokes `pkg-config`; the actual fetch location
is a separate macro, matching real ports' own split (`MASTER_SITES` in
the `Makefile`, not the port's own name).

Both kinds share the same fetch → verify → extract → patch pipeline;
they differ only in what happens after patching.

## Declaring what to fetch

```makefile
LIB=zlib
IMPORT=fetch:zlib
FETCH_URL=https://zlib.net/zlib-1.3.1.tar.gz \
          https://github.com/madler/zlib/releases/download/v1.3.1/zlib-1.3.1.tar.gz
FETCH_PATCHES=fix-arm64-build.patch
SRCS=deflate.c inflate.c trees.c zutil.c adler32.c crc32.c
IMPORT_HEADERS=zlib.h zconf.h
.include <mk.lib.mk>
```

- **`FETCH_URL=<url> [<url> ...]`** — one or more full URLs to the
  *same* distfile, tried in order until one succeeds (mirrors real
  `MASTER_SITES`' own fallback role, simplified: each entry here is
  already a complete file URL, not a directory + separate filename
  macro — v1 doesn't need the extra indirection a whole ports tree's
  worth of shared mirrors does).
- **`distinfo`** (a file, not a macro) — committed alongside the
  module's `makefile`; see below.
- **`FETCH_PATCHES=<name> [<name> ...]`** — files under the module's
  own `patches/` directory, applied in order via `patch -p1` against
  the extracted work tree (`patch -p1` chosen as the modern default —
  what a `git diff`-produced patch already expects; not real ports'
  own convention, a deliberate simplification for v1).
- **`SRCS=`** — for `fetch:` (source) only, **required**, not
  auto-discovered. Paths are relative to the resolved work-tree root
  (`WRKSRC`-equivalent, see below). Auto-discovering every `.c`/`.cpp`
  under an arbitrary upstream source tree would just as easily pull in
  its own tests/examples/tools — an explicit list is the safe default,
  playing the role a real port's own `Makefile`/build system would
  otherwise take in deciding what actually gets compiled.
- **`IMPORT_HEADERS=`** — reused unchanged from `25-imported-libraries.md`;
  same promotion destination, same visibility rules.

Per-target specificity (a different `FETCH_URL=`/`FETCH_PATCHES=` for
one `TARGET`/`TARGET_ARCH`) reuses the existing `mk/` hook cascade
(`REQ-local-mk-arch-variant-req`) — `mk/pre.${TARGET}.mk` or
`mk/pre.${TARGET}_${TARGET_ARCH}.mk` overriding the macro, exactly like
any other per-target override in this project. No new per-target
mechanism.

## `distinfo` — checksums only

(`REQ-fetch-distinfo-checksum-req`)

A small, committed, plain-text file at `<module>/distinfo`:

```
SHA256 (zlib-1.3.1.tar.gz) = 9a93b2b7dfdac77ceba5a558a580e74667dd6fede4585efcb4a10a8c9d63104
SIZE (zlib-1.3.1.tar.gz) = 1497445
```

One `SHA256 (<basename>) = <hex>` / `SIZE (<basename>) = <bytes>` pair
per distfile, keyed by the downloaded file's own basename (the last
path segment of whichever `FETCH_URL=` entry actually succeeded) —
matching real `distinfo`'s own format exactly, minus the `TIMESTAMP`
line (purely informational there, not load-bearing for verification;
deferred, not a correctness gap). A checksum mismatch is a parse-time
`.error` naming the module, the expected and actual hashes, and the
file — extraction never proceeds on unverified content. SHA-256, not
`cksum` (the algorithm this project already uses elsewhere for
cache-invalidation fingerprints, e.g. `import-resolution-cache-req`) —
that distinction matters here specifically: `cksum` answers "did MY OWN
inputs change," CRC-32-class and not collision-resistant; verifying
*third-party, untrusted downloaded content* against tampering or
corruption needs a real cryptographic hash.

## Fetch, verify, extract, patch

The whole pipeline lives in a `.PHONY` recipe, `_fetch_import:`, a
prerequisite of the compile rules (source kind) or the staging step
(binary kind) — never run merely from parsing the makefile, since
`IMPORT=fetch:`/`fetch-bin:` resolution itself (`_IMPORT_SOURCE`,
`_IMPORT_KIND`, `_IMPORT_WRKSRC`) is pure parse-time string manipulation
with no network I/O, unlike `pkg:`/`prefix:`'s real `!=` shell-outs.

1. **Fingerprint check**: a `cksum` of `FETCH_URL=`/`FETCH_PATCHES=` is
   compared against `<module>/work/.extract-fp` (written on the last
   successful run); an unchanged fingerprint skips the entire pipeline.
2. **Fetch**: try each `FETCH_URL=` entry in order until one succeeds,
   saving to `<module>/distfiles/<basename>` — an entry whose basename
   already exists in `distfiles/` is reused without any network access,
   which is also what makes a fingerprint change with the *same*
   basename (e.g. a mirror swapped out) succeed without re-fetching.
3. **Verify**: SHA-256 against `distinfo`; a clean failure naming the
   module, the distfile, and both hashes on mismatch — extraction never
   proceeds on unverified content, whether the distfile was just
   downloaded or already sitting in `distfiles/`.
4. **Extract**: into `<module>/work/_extracted/`. If the archive
   extracts into exactly one top-level directory, that directory is used;
   otherwise `work/_extracted/` itself is (auto-detected, matching the
   common single-top-level-directory tarball convention most distfiles
   already follow — an explicit override is deferred, not needed for a
   first real case). Either way, its contents are then `cp -a`'d into a
   **fixed** `<module>/work/_resolved/` — this, not the archive's own
   (only known post-extraction) top-level name, is `_IMPORT_WRKSRC`: the
   one parse-time-knowable path `SRCS=`/`IMPORT_HEADERS=` resolve
   against, sidestepping the chicken-and-egg of needing the extracted
   name before extraction has happened.
5. **Patch**: each `FETCH_PATCHES=` entry, in order, via `patch -p1`
   from `work/_resolved/`.

A genuine re-extraction (fingerprint changed, real work done) clears
`${_OBJDIR}` before recreating it, so a stale `.o` can never survive a
source change via an mtime race against a distfile's own, possibly old,
embedded timestamps — then writes the new fingerprint only on success.

Both `distfiles/` and `work/` are per-module, not shared across
modules or target keys — the same extracted (and patched) source is
reused for every `TARGET`/`TOOLCHAIN` build of that module, only the
*compiled* objects differ per target key
(`REQ-fetch-cache-never-committed-req`). `bmake clean` removes `work/`
unconditionally (build-output-like) and `distfiles/` only under
`CLEAN_ALL_TARGETS=yes` (an expensive-to-refetch cache, mirroring real
ports' own `clean`/`distclean` split); `patches/` is committed source
and is never touched by `clean`.

## Source kind (`fetch:`)

(`REQ-fetch-import-source-req`)

After patching, the resolved `SRCS=` entries (relative to the work-tree
root) are compiled through Bmake It's **own existing compile pipeline**
— `CFLAGS`/`CXXFLAGS`/`WARN=`/`CXXSTD=`/`SANITIZE=`/header-dependency
tracking, all of it, unchanged. No delegation to the upstream project's
own build system (no `./configure`, no `cmake`) — the fetched, patched
files are treated exactly like a `.y`/`.l` grammar's generated `.c`
already is: an ordinary compiled source this project's own toolchain
invocation handles directly. Same "no third-party build-system
plumbing" stance already established for Qt
(`qt-development-without-plumbing-req`), now consistent across every
external-code mechanism in the project, not just Qt's.

Once compiled, the result is an **ordinary library module** for every
other purpose: `LIB_SHARED=`, `LIBS=` transitivity (its own
`lib<LIB>.linkdeps` gets written exactly like a normally-compiled
module's, `import-link-transitivity-req`), `INPUTS_HASH_EXTRA=`-driven
rebuild-on-change (the resolved checksum and patch set feed into it, so
a changed `FETCH_URL=`/`distinfo`/patch set triggers a real rebuild),
copy-up, everything.

## Binary kind (`fetch-bin:`)

(`REQ-fetch-import-binary-req`)

Fetch/verify/extract/patch are identical. What happens after differs:
instead of compiling, the extracted `lib<LIB>.{a,so,dylib}` and
`IMPORT_HEADERS=` entries are staged directly — reusing the **exact
same** `_stage_import:` mechanism `pkg:`/`prefix:` already use
(`25-imported-libraries.md`), just pointed at the resolved work-tree
root instead of a system prefix or `pkg-config`'s own answer. No new
staging code, no new promotion logic — only the *source* of
`_IMPORT_CFLAGS`/`_IMPORT_LIBDIR` changes.

## Testing

Self-contained, per this project's own established harness convention
(no real network access from a test — `tests/cases/*` already ship
their own fake prefixes/`.pc` files for `pkg:`, the same discipline
applies here): a **`file://` URL** pointing at a fixture `.tar.gz` the
test itself builds at run time (source content and checksum embedded
in the test, not committed) stands in for the real distribution site.
`FETCH_URL=` points at it; the rest of the pipeline runs unmodified.
Coverage, mirroring the rigor `import-resolution-ladder-req`'s own test
list already set:

- `tests/cases/60-fetch-import-source`: a `fetch:` module builds from a
  genuinely fetched, genuinely extracted tarball (explicit `SRCS=`),
  compiled and run for real; a `FETCH_PATCHES=` entry actually changes
  the fetched source's behavior, verified by running the result, not
  just by confirming `patch` exited 0; a fingerprint change whose
  `FETCH_URL=` now points at an unreachable path but shares the
  already-downloaded distfile's basename still succeeds (build-level
  cache hit); multiple `FETCH_URL=` mirrors with the first unreachable
  fail over to the second, from a genuinely fresh extraction.
- `tests/cases/61-fetch-import-checksum-mismatch`: a checksum mismatch
  is a clean build failure naming the module/distfile/both hashes, not
  a silent continue — proven by deliberately committing a `distinfo`
  that doesn't match the served file — and the corrupted distfile is
  not left behind masquerading as valid.
- `tests/cases/62-fetch-import-binary`: `fetch-bin:` stages a prebuilt
  library and header without compiling anything, and a consumer links
  and runs against it.

## Not yet decided / deferred

- Explicit `WRKSRC=`-style override for a distfile that doesn't extract
  into a single top-level directory — auto-detection covers the common
  case; not designed further here.
- `FETCH_PATCH_ARGS=` (an escape hatch for a patch set that needs
  something other than `-p1`) — deferred until a real case needs it.
- Mirror-list indirection (`FETCH_SITES=` + a separate filename macro,
  matching real `MASTER_SITES`/`DISTFILES` more closely, so several
  distfiles could share one site list) — v1's `FETCH_URL=` already
  covers the one-distfile-per-module case this project's own module
  model assumes; revisit only if a real case needs more than one
  distfile per module.
- Interaction with `install`/`distrib` (parked project-wide already,
  `install-distrib-rewriting-deferred-topic`).
