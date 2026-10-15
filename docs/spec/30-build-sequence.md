# Bmake It — 30: Build Sequence & Dependency Ordering

Status: DRAFT, synthesized from confirmed `project-model/req/` objects.

## Build strategy: fused, not phased

Build strategy is **fused compile+link (and header-generation) per
module/framework** — matching real `bsd.*.mk` idiom directly (each
directory's `make` invocation builds its own target fully in one pass),
**not** a global compile-all-then-link-all split
(`REQ-fused-build-per-module-full-dependency-order-req`).

This was a deliberate choice over the alternative (compile everything
everywhere first, fully parallel, then link in dependency order): fused
per-module builds handle both compile-time dependencies (consumed
promoted generated headers) and link-time dependencies (`LIBS=`) with a
single mechanism — "fully build the dependency before starting the
dependent" — rather than needing separate compile-phase and link-phase
ordering logic.

## The full sequence

1. **Resolve `PARENT_WS`** — ordered fallback workspace search list
   (`REQ-workspace-parent-macro-absolute-req`).
2. **Auto-discover frameworks** at workspace root: any immediate
   subdirectory containing a `makefile` that declares `PREREQS=` (now
   mandatory, even empty — this doubles as the discovery signal;
   `build/`/`distrib/` are naturally excluded, having no such file)
   (`REQ-framework-discovery-signal-req`).
3. **Resolve each framework's `PREREQS`** — determines both header search
   paths (`20-headers-and-linking.md`) and framework build order: a
   framework builds only after every framework it lists has been
   *fully* built. No cycle detection — misordering/cycles surface only
   as ordinary build errors (`REQ-framework-build-order-follows-prereqs-graph-req`,
   `REQ-prereqs-misorder-no-validation-req`).
4. **Auto-discover modules** within each framework: any immediate
   `*.m`-suffixed subdirectory (`REQ-modules-and-frameworks-auto-discovered-req`).
5. **Build each module** as one fused unit, in a topological order over
   two edge types: a module's `LIBS=` entries, and consumption of a
   sibling/prereq's *promoted* generated header. Either edge requires
   the depended-on unit to be fully built first.
6. **Copy each module's artifact** up to the framework's `build/<KEY>/
   bin/` or `lib/`, then **copy the framework's `bin/lib/`** up to the
   workspace's `build/<KEY>/bin/lib/` (`REQ-aggregation-step-copies-outputs`).
7. **Resources cascade the same way** — module → framework → workspace,
   each level applying its own `common/os/os_arch` 3-layer overlay
   before copying up (`REQ-share-overlay-copy-order`).

## Ordering, precisely

| Level | Constraint |
|---|---|
| Across frameworks (`PREREQS`) | Whole framework must be fully built before any dependent framework can build |
| Within a framework, across modules (`LIBS`/generated headers) | A module can't start until every sibling it depends on (via `LIBS=` or a consumed promoted header) has been *fully* built |

Compiling a module that only depends on hand-written headers has no
ordering requirement — hand-written headers are pure source, resolved
directly, with nothing to wait for.

An `IMPORT=`-based library module (`25-imported-libraries.md`)
participates in this ordering identically to a compiled one — its
`LIB=` is what a consumer's `LIBS=` matches against, regardless of
whether the module compiles or imports. The dependency-order query
itself (`gen-mod-order.sh`) must evaluate each module's makefile with
the same `.CURDIR` a real build of that module would see — fixed as
part of adding `IMPORT=`, since its own resolution logic is `.CURDIR`-
sensitive (module-local `mk/` hook lookup) in a way `LIB=`/`LIBS=`/
`PROG=`'s plain literal assignments never were before
(`REQ-gen-mod-order-correct-curdir-req`).

### When the order cannot be determined

Both generators (`gen-mod-order.sh` for modules, `gen-fw-order.sh` for
frameworks) answer "what does this unit depend on?" by running a nested
`bmake -V` on its makefile. If that query fails, the build **stops**,
with an error naming the module or framework queried, the exact command,
and bmake's own message — nested, one level per generator, so the
workspace-level error shows the framework query that failed and, inside
it, the module query that caused it
(`REQ-order-query-failure-is-error-req`). A `*.m` directory with no
`makefile` is named as such. In a `-V` query rather than a build, the
same failure is printed as a warning and the query still answers, as
for every other parse-time error
(`REQ-order-failure-in-query-is-warning-req`). There is no fallback to
alphabetical or discovery order: a failed query looks exactly like "no
dependencies", and building in that order fails later with a "not built
yet" or missing-header error far from the cause. This happened twice
before the rule existed — on Linux (2026-08-31) and on Cygwin
(2026-10-15).

The nested query needs bmake's own system rules (`sys.mk`), whose
directory differs per host (`/usr/share/mk` on the BSDs,
`/usr/share/bmake/mk` on Cygwin and Debian, `/opt/local/share/mk` on
MacPorts, ...). They are looked for, in order, in `BMK_SYS_MK=` if set,
in the directories the invoking bmake itself searches (`.SYSPATH`, passed
down as `MAKESYSPATH`), then in the usual install directories. Finding
none is an error listing every directory searched
(`REQ-order-query-sys-mk-located-req`).

A module whose `IMPORT=` cannot be resolved does not stop the order
query: that error is skipped during `-V`, as `REQUIRES=`'s is, and
raised when the module itself is built, so every other module and
framework is still attempted (`REQ-import-unresolved-fails-module-not-order-req`).

## Collision handling during copy-up

The copy-up mechanism (step 6/7) is **diff-aware**
(`REQ-copy-up-collision-diff-aware-req`):

- **Identical content** colliding at the same destination path → silent,
  no message.
- **Differing content, genuine collision** (e.g. two modules or
  frameworks independently producing a same-named artifact) → a warning
  is emitted, but the build still proceeds (overwrite, not a hard stop).
- **Differing content from the same producer** (a module or framework
  overwriting its own earlier output after a legitimate rebuild) →
  **silent**: a rebuilt artefact is expected to differ from its previous
  copy. The previous producer of each name is recorded in
  `build/<KEY>/.copy-up-origin/<bin|lib|share>.tsv`, beside the
  aggregation directory rather than inside it so it is never shipped; a
  name with no recorded producer still warns
  (`copy-up-collision-different-modules-only-req`).
- **Differing content, deliberate `share/` specificity overlay** (a
  platform-specific variant intentionally overwriting the generic one)
  → **no warning at all** — this is expected, by-design behavior, not a
  collision.

## Caching

Two distinct, mechanically-similar caches, both modeled on real BSD
make's own `.depend` idiom (a generated file, regenerated via an
explicit or detected-stale trigger, consumed via `.include` on
subsequent runs) rather than recomputing from scratch on every `make`
invocation:

1. **`PARENT_WS`/`PREREQS` resolution cache** — workspace/framework-level:
   caches the dependency-graph resolution (header search paths + build
   order) so it isn't re-walked on every invocation
   (`REQ-prereqs-resolution-cached-like-depend-req`).
2. **Per-module `.depend`** — file-level, `mkdep`-style: which source
   files include which headers (transitively), so touching a header only
   triggers recompilation of the `.o` files that actually depend on it,
   not a full module rebuild (`REQ-mkdep-style-header-dependency-tracking-req`).

Exact generated filenames, staleness-detection mechanism, and
regeneration triggers for **both** caches are deliberately deferred
until real `bsd.*.mk`/FreeBSD's `build.*.mk` infrastructure can be
checked hands-on for what they already provide
(`OBS-cache-mechanism-needs-empirical-check`).
