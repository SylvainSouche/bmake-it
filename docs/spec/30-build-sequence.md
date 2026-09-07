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

## Collision handling during copy-up

The copy-up mechanism (step 6/7) is **diff-aware**
(`REQ-copy-up-collision-diff-aware-req`):

- **Identical content** colliding at the same destination path → silent,
  no message.
- **Differing content, genuine collision** (e.g. two modules or
  frameworks independently producing a same-named artifact) → a warning
  is emitted, but the build still proceeds (overwrite, not a hard stop).
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
