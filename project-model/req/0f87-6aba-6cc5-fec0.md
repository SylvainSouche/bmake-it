---
schema_version: 2
id: 0f87-6aba-6cc5-fec0
alias: requires-software-prereq-req
type: req
status: confirmed
origin: requires-software-prereq-dec
created: 2026-09-28
rel_decided_by: [0f87-6aba-6cbc-5881]
rel_refines: [0f87-6aa1-0496-b3d2]
generator: model.py/2.4.0
checksum: 12daae198f76
---

# REQUIRES=<name> [<name> ...] on any module (mk.prog.mk/mk.lib.mk) names external prerequisite software that must already be present on the host -- not fetched, imported, or staged by Bmake It. Each name is checked via pkg-config --exists first, then command -v as a fallback; a missing one is a parse-time .error naming the module and which REQUIRES= entry could not be found, before any real build work (including a slow FETCH_BUILD= configure) starts

Distinct from `IMPORT=`/`fetch:`/`fetch-bin:`/`FETCH_BUILD=`: those
mechanisms *acquire* a library (pkg-config resolution, a fetched
distfile, a delegated build) and stage it into the build. `REQUIRES=`
acquires nothing and stages nothing -- it is a pure precondition check,
for the case a real project (GDAL, PDAL) hits routinely: a system-level
dependency (PROJ, GEOS, SQLite, libcurl, ...) that the module's own
`FETCH_BUILD_CMD=`/preset build already knows how to find on its own
(via its own `pkg-config`/`find_package`-equivalent), but that Bmake It
itself never resolves or imports. Without `REQUIRES=`, a missing one
surfaces only once the upstream build's own configure step reaches it --
possibly minutes into a `FETCH_BUILD=cmake` run.

**Scope, deliberately kept small** ("a la cmake, but not with all that
plumbing, just check or error" -- the user's own words): no Find-module
system, no per-package version constraints, no per-platform
install-command database to maintain, no target-based dependency graph.
One macro, two checks, one clean error.

**Not cross-sysroot-aware**: the check runs against the HOST's own
`pkg-config`/`PATH`, the same as `IMPORT=pkg:`'s own non-cross-aware
fallback. For a genuinely cross-compiled target, "is this installed on
the build host" is often the wrong question (the TARGET's own sysroot
is what actually matters) -- out of scope here, matching this project's
existing, already-deferred cross-sysroot package resolution story;
`REQUIRES=` mainly answers "is the build-host tooling/library present
for a native build," which is exactly the lasviewer/GDAL/PDAL case that
prompted this.
