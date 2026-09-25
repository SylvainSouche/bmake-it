# Bmake It unit tests

## Cross-platform verification (2026-08-31)

All 27 cases pass on every platform family CON-cross-platform-targets
requires, run for real rather than assumed from the macOS results:

| Platform | How | Toolchain |
|---|---|---|
| macOS (MacPorts) | native | `/opt/local/bin/bmake` |
| Linux (Debian bookworm) | Colima/Docker VM | `pkg install bmake gcc` |
| NetBSD 10.1 (arm64) | QEMU VM (`hvf` accel) | native `/usr/bin/make` + base clang, nothing installed |

Running on real Linux and a real BSD (not just macOS) is what surfaced two
bugs invisible on macOS alone: a self-reentrant nested-`bmake` invocation
(`gen-mod-order.sh`/`gen-fw-order.sh`, now fixed with absolute-path
resolution and atomic cache writes) and archives silently corrupted by
macOS AppleDouble sidecar files (`pack-cases.sh` now strips them). Both are
model requirements now (`nested-invocation-reentrancy-guard-req`), not just
patches.

## Design

- **Orchestration is pure shell** (`harness/run-tests.sh`), not make — so there
  is no nested-make contamination of `MAKEFLAGS` / `MAKELEVEL`.
- **Each test is an independent archive** under `archives/*.tar.gz`.
  The runner extracts it into a private work directory, runs `run.sh`,
  then deletes the work directory (unless `KEEP_FAILED=1`).
- **Isolated bmake**: every invocation goes through a wrapper that clears
  `MAKEFLAGS`/`MAKELEVEL`/`MFLAGS` and sets `MAKESYSPATH` + `BMK_MKDIR`.

## Running

```sh
# from the Bmake It tree
sh tests/harness/run-tests.sh           # all tests
sh tests/harness/run-tests.sh 10-       # filter by substring
KEEP_FAILED=1 sh tests/harness/run-tests.sh   # keep failing work dirs
```

On MacPorts, `bmake` is not at `/usr/bin/bmake` (the harness's default) —
set `BMAKE` as well as `BMK_SYS_MK`:

```sh
export BMK_SYS_MK=/opt/local/share/mk
export BMAKE=/opt/local/bin/bmake
sh tests/harness/run-tests.sh
```

## Regenerating archives from cases/

```sh
sh tests/harness/pack-cases.sh
```

## Case index (spec + implementation risk)

| ID | Focus |
|----|--------|
| 01 | Framework discovery via `PREREQS=` signal; ignore `build/`/`distrib/` |
| 02 | `PREREQS` mandatory even when empty |
| 03 | Module discovery `*.m` only |
| 04 | Module topological order from `LIBS=` |
| 05 | Framework topological order from `PREREQS=` |
| 06 | Cycle detection in module order |
| 07 | `PROG`/`LIB` default to module directory name |
| 08 | `LIB_SHARED=NO` → static only |
| 09 | Versioned shared library name (`SHLIB_MAJOR`) |
| 10 | Full prog + shared-lib link end-to-end |
| 11 | Three-level headers + prereq public headers |
| 12 | `LIBS=` is link-only (private headers not exposed) |
| 13 | Target key / `OS_ARCH` / `TOOLCHAIN` suffix |
| 14 | `clean` scope does not wipe other target keys |
| 15 | External `LIBS` entries ignored by topo sort |
| 16 | `src/` auto-discovery |
| 17 | `install DESTDIR= PREFIX=` |
| 18 | `PARENT_WS` absolute path |
| 19 | `SUBDIR` isolation (workspace must not leak into modules) |
| 20 | Empty workspace builds |
| 21 | Native `CFLAGS+=` append |
| 22 | Empty `SRCS` border behaviour |
| 23 | Linux target-key ABI suffix (`glibc` omitted, `musl` shown) |
| 24 | `bmake help` at workspace/framework/module level |
| 25 | `add-parent` appends `PARENT_WS=`; usage error without `WS=` |
| 26 | `install` refuses on an unbuilt workspace |
| 27 | Workspace-root `share/` is not overlay-copied into build output |
| 28 | `PREREQS=` naming a framework that only exists in a `PARENT_WS` workspace: header+lib resolve there, binary actually runs |
| 29 | `PREREQS=` framework present in both the current workspace and a `PARENT_WS`: the local one wins for compile, link, and run |
| 30 | `add-prereq` appends `PREREQS=`, preserves order across repeated calls; usage error without `FW=` |
| 31 | `run` resolves and executes `PROGRAM=` with the right dynamic-library search path, from the workspace root, a framework dir, or a module dir; `ARGS=` passthrough; usage/not-built error paths |
| 32 | `add-prereq FW=Lib` on a sibling framework in the *same* workspace actually enables header visibility + link + run, not just the `PREREQS=` text edit |
| 33 | `add-prereq FW=Lib` where `Lib` only exists in a `PARENT_WS` workspace — same real build+link+run guarantee as 28, established via `add-prereq` instead of hand-written `PREREQS=` |
| 34 | `add-prereq FW=Lib` where `Lib` exists in both the current and a `PARENT_WS` workspace — local must still win, established via `add-prereq` |
| 35 | Linking a module before its `LIBS=` dependency is built fails with an explicit "prerequisite library X has not been built yet" diagnostic (not an opaque linker error); the same module links and runs normally once the dependency is actually built |
| 36 | Two frameworks independently producing a same-named `share/` artifact at workspace-level copy-up: byte-identical content copies silently, differing content warns but still overwrites (build succeeds, last-copied-wins) |
| 37 | The `share/common → share/<os> → share/<os>_<arch>` overlay cascade across every layer-presence combination: a file unique to any one layer survives; where two-plus layers define the same file, the most specific present layer wins |
| 38 | A framework present in both the current workspace and a `PARENT_WS`, where only the *parent's* copy has a more-specific `share/<os>` override: the local copy is used in its entirety (its own `share/common` only) — no cross-workspace layer fallback, mirroring case 29's shadow principle applied to `share/` |
| 39 | A C++ program (`SRCS` has `.cpp`) links with `${CXX}`, not `${CC}` — exercises real C++ runtime support (exceptions) at link time |
| 40 | A C++ shared library *and* the C++ program consuming it both link with `${CXX}`; the exception is thrown from inside the `.so` itself |
| 41 | `LINK_CXX=yes`: a pure-C module linking a static C++ library fails to link (undefined C++ runtime symbols) without it, and links/runs correctly with it |
| 42 | A broken module + a good module: `bmake` (build) exits non-zero and names the broken module at both framework and workspace level, but the good module still builds (`FAIL_FAST=no`, the default); `FAIL_FAST=yes` stops before the good module is even attempted |
| 43 | Same as 42, for `bmake test`: a genuinely failing atf-c test + a genuinely passing one |
| 44 | Header dependency tracking (gcc/clang `-MMD -MP`): a no-op rebuild recompiles nothing; a module-private header change and a framework-public header reached only via `PREREQS=` (not the consumer's own `src/`) both trigger exactly the affected object to recompile |
| 45 | `bmake` then `bmake SANITIZE=address` actually recompiles (not just relinks stale objects), and the resulting binary genuinely crashes under ASan on a real heap-buffer-overflow; a repeated `bmake SANITIZE=address` recompiles nothing, and dropping back to plain `bmake` recompiles again |
| 46 | `mk.local.mk`'s hook cascade: all four conventional names (`pre.mk`, `pre.${TOOLCHAIN}.mk`, `pre.${TARGET}.mk`, `pre.${TARGET}_${TARGET_ARCH}.mk`) fire when they match (values queried from the real running bmake, not hardcoded), and a hook keyed to a different OS does not |
| 47 | `IMPORT=pkg:<name>` end to end against a real (self-contained, fake) pkg-config `.pc` file: header+lib staging, a plain `LIBS=`-consuming module needs no IMPORT-specific change, only `IMPORT_HEADERS=` is visible (a sibling header in the same prefix is not), and an unresolvable import fails loudly naming what was tried |
| 48 | `IMPORT=` resolution precedence: each ladder step (env/CLI, `mk/` hook, pkg-config, probing) proven individually reachable, then proven to lose to the next higher-precedence step once both are available |
| 49 | Link transitivity, compiled side: a three-level static chain (app → libb → libc) where `app.m` declares only `LIBS=b` -- `libc` still links and runs, pulled in via `libb`'s own recorded `.linkdeps` |
| 50 | Link transitivity, `IMPORT=` side: a fake pkg-config package's real `Libs.private` entry follows it into a consumer that never mentions the private dependency at all |
| 51 | `CXXSTD` defaults to `c++17` — a genuine C++20-only construct (`consteval`) fails under the default and builds/runs correctly with `CXXSTD=c++20` |
| 52 | `OPENMP=yes` builds a real `omp parallel for` program that genuinely uses more than one thread; a compiler that can't accept `-fopenmp` at all (a fake `CC`) gets a clean `.error`, not an opaque compile failure |
| 53 | `WARN=none` suppresses a vendored module's own warnings; `PUBLIC_HEADERS_SYSTEM=yes` on its framework means a consumer in a different framework isn't flooded with warnings from the vendored public header either (`-isystem`) — but the consumer's own code still reports its own warnings normally |
| 54 | Header dependency tracking, the fourth case: a PROMOTED GENERATED header (yacc `-d` output, `INCL=`-promoted) triggers a cross-framework consumer to rebuild when regenerated with different content, same as a hand-written header |
| 55 | `IMPORT=`: `_PKG_CONFIG_EXTRA_DIRS` (settable via a `mk/` hook) is searched for `.pc` files pkg-config's own defaults and `PKG_CONFIG_PATH` would never reach; without it, resolution fails cleanly |
| 56 | `IMPORT=`: `PREREQS=` alone (no `LIBS=`) lets a consumer `#include` the imported header (compiles) but fails to *link* (undefined symbol) — adding `LIBS=` then links and runs, exactly like a compiled library |
| 57 | `IMPORT=`: an externals framework shared via `PARENT_WS`, with a local shadow of the same framework name (both `IMPORT=`-resolved) — the local one wins for compiling, linking, and the actual symbol run, mirroring case 29 for compiled frameworks |
| 58 | The persisted "swap test": the same library, once compiled from source and once `IMPORT=`-resolved, with the consumer module never touched across the swap — both link and run correctly |
| 59 | `IMPORT=` resolution caching, verified with a real call-counting `pkg-config` stub: the first build makes real calls, an unchanged second build makes none, and a changed `PKG_CONFIG_PATH` triggers real re-resolution |
| 60 | `IMPORT=fetch:` (source kind): a genuine fetch+SHA-256-verify+extract+patch+compile+run against a `file://` fixture distfile; `FETCH_PATCHES=` actually changes the fetched source's behavior (verified by running the result); a fingerprint change pointing `FETCH_URL=` at an unreachable path but the same already-downloaded basename still succeeds; multiple `FETCH_URL=` mirrors with the first unreachable fail over to the second |
| 61 | `IMPORT=fetch:`: a `distinfo` SHA-256 that doesn't match the served distfile fails the build cleanly (module/distfile/both hashes named, no corrupted file left behind), and a corrected `distinfo` then builds normally |
| 62 | `IMPORT=fetch-bin:` (binary kind): a prebuilt `lib+header` tree is fetched/verified/extracted and staged via the same `_stage_import:` mechanism `pkg:`/`prefix:` use — no compile step — and a consumer links and runs against it |
| 63 | `IMPORT=pkg:` against a real macOS-style dylib symlink chain (`libfoo.dylib` → `libfoo.34.dylib` → `libfoo.34.3.5.dylib`, matching real MacPorts/Homebrew layouts): both the unversioned and SONAME-equivalent major-version names must stage as valid, non-dangling, non-absolute symlinks, proven by actually running the linked consumer, not just inspecting the staged files (macOS-only; skips elsewhere) |

Exit code 77 from `run.sh` is treated as SKIP.

## Coverage plan against the spec (2026-09-02 assessment)

Cross-checked all 38 cases against every confirmed leaf requirement in the
model. Cases 23-38 above closed the gaps found among requirements that are
actually **implemented**:

| ID | REQ |
|----|-----|
| 23 | `linux-libc-default-glibc-req` |
| 24 | `help-target-req` |
| 25 | `add-prereq-add-parent-convenience-targets-req` (the `add-parent` half) |
| 26 | `install-requires-prebuilt-target-req-v2` (the negative path specifically — test 17 only covered the success path) |
| 27 | `no-workspace-level-share-source` (NREQ). `no-identitycard-special-file` is already covered implicitly: every case from 01 on builds a real framework using nothing but `makefile`+`PREREQS=`. |
| 28 | `headers-resolved-from-source-req`, parent-only case |
| 29 | `headers-resolved-from-source-req`, local-shadows-parent case |
| 30 | `add-prereq-add-parent-convenience-targets-req` (the `add-prereq` half, text-editing behavior only) |
| 31 | `run-target-req`, `run-target-any-workspace-dir-req` |
| 32 | `add-prereq-add-parent-convenience-targets-req` × `headers-resolved-from-source-req`, same-workspace case (no existing case exercised this topology — 11 only compiles, never links+runs) |
| 33 | `add-prereq-add-parent-convenience-targets-req` × `headers-resolved-from-source-req`, parent-only case, via `add-prereq` rather than hand-written `PREREQS=` |
| 34 | `add-prereq-add-parent-convenience-targets-req` × `headers-resolved-from-source-req`, local-shadows-parent case, via `add-prereq` |
| 35 | `link-time-not-yet-built-guard-req` |
| 36 | `copy-up-collision-diff-aware-req`, genuine (non-overlay) collision case |
| 37 | `share-overlay-copy-order-req`, full layer-presence matrix (previously only ever exercised in the trivial "all three layers agree" shape, never per-layer-unique or partial-override combinations) |
| 38 | `headers-resolved-from-source-req`'s "local wins entirely, no merging" principle, applied to `share/` instead of headers/libs — previously untested for this subsystem specifically |

`run`, `add-prereq`, and the link-time not-yet-built guard are now
implemented (2026-09-02) — mk.common.mk (shared by all four roles),
mk.framework.mk, and mk.prog.mk/mk.lib.mk respectively — closing the
exclusions noted in the prior assessment. copy-up is now diff-aware too
(mk.prog.mk/mk.lib.mk/mk.framework.mk copy-up targets, via the new
scripts/diff-aware-copy.sh). Still excluded, because still
unimplemented: cross-toolchain paths, binary packaging, and `.depend`/`-MD`
tracking — none of these have real behavior yet, so no test can validate
them; they belong with those features, not before them.

Note on the link-time guard's scope: it checks that each `LIBS=` entry's
build artifact *exists* before linking (per the confirmed REQ). It
deliberately does not attempt an "is it up to date" staleness check — that
would need real source-to-artifact dependency tracking (the still-unimplemented
`-MD` req) to be precise; a coarse mtime heuristic without it would risk
spurious failures on legitimate builds. Staleness detection should ride on
top of `-MD` tracking once that lands, not ship as a guess now.

Note on the diff-aware copy-up's scope: it covers the three `copy-up:`
targets (module→framework bin/lib, framework→workspace bin/lib/share) —
these are where two *independently built* things can genuinely collide.
The framework-local `share/common → share/<os> → share/<os>_<arch>`
specificity cascade inside `_aggregate:` is deliberately left on plain
`cp -a`, unchanged: per the confirmed REQ, a more-specific layer
overwriting a less-specific one there is expected, by-design behavior and
must never warn, which is exactly what leaving it alone already gives.

Note on cases 37/38: `TARGET=`/`TARGET_ARCH=` are lazily-assigned (`=`) in
mk.common.mk, so `bmake -V TARGET` prints them unexpanded (a bmake quirk —
`:=`-built variables like `OS_ARCH` resolve fully, plain `=` ones don't).
Both tests derive TARGET/TARGET_ARCH by splitting `bmake -V OS_ARCH`
instead, same as case 13-target-key already relies on.

Lower priority, noted but not designed as archives:

- **`debug-release-via-native-bsd-flags-req`** — `DEBUG_FLAGS=-g` should reach the actual compile line and no project-specific `MODE=` should exist. Could fold into a `CFLAGS`-inspection assertion similar to test 21.
- **`module-name-case-sensitivity-req`** — the requirement is "no enforcement," which is filesystem-dependent and not meaningfully assertable in a portable test; skip (exit 77) on case-insensitive filesystems if ever written.
- **`shlib-major-minor-cross-platform-emission-req`**, ELF half — the FreeBSD/Linux symlink-chain behavior (as opposed to the macOS dylib path test 09 already covers) can't be tested until cross-compilation is real; it's a stub today, same as the toolchain paths.
- **`build-system-self-test-harness-req`** — satisfied by this suite's own existence; a test of the test harness would be diminishing returns.
- **`no-four-level-header-visibility`** (NREQ) — already implicitly covered by test 11 asserting exactly three include paths; not worth a separate case.
