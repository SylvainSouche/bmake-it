# Bmake It — 60: BSD Make Feature Validation Plan & Results

Status: **PARTIALLY EXECUTED**. Tier 1 items 1.1/1.2/1.4, Tier 2 items
2.1/2.2/2.3/2.4 tested empirically; results below. Item 1.3 (macOS/
MacPorts `bsdmake`) could not be tested — no macOS environment
available; this now also covers the `-MD` dependency-tracking question
raised in 2.2, see below. Items 3.1, 3.2 not yet tested. Not itself a
project-model object — see
the cited `OBS`/`DEC`/`REQ` aliases in `project-model/` for the
authoritative record; this document is a synthesis for quick reference.

## Test environment actually used

No FreeBSD or macOS box was available. Instead:
- **`bmake`** (the `bmake` Debian/Ubuntu package — a portable build of
  NetBSD's `make`, same lineage as FreeBSD `bmake` and MacPorts
  `bsdmake`), installed via `apt`.
- **Real FreeBSD `share/mk`**, fetched via sparse checkout of
  `freebsd/freebsd-src` from GitHub, used with the portable `bmake`
  binary via `-m <path>`.
- **NetBSD's own bundled `mk-netbsd` set** (shipped inside the `bmake`
  package itself, self-consistent with the `bmake` binary) — used as a
  second, independent check to distinguish real findings from artifacts
  of mixing an unrelated `bmake` binary with a raw FreeBSD source
  checkout that's missing surrounding infrastructure.
- A working C toolchain (`gcc`), `bison`/`flex` (providing `yacc`/`lex`).

This is a reasonable stand-in for FreeBSD/NetBSD validation, but **not**
a substitute for testing on your actual macOS+MacPorts and FreeBSD
machines — several results below are flagged as needing that
re-verification.

---

## Tier 1 — results

### 1.1 — `TARGET=`/`TARGET_ARCH=` for arbitrary projects

**Result: risk CONFIRMED, design corrected.**
`bmake TARGET=freebsd TARGET_ARCH=arm64` on an amd64 host, against a
minimal `PROG=hello` module, produced a plain **x86-64** binary — `CC`
never changed from bare `cc`. `TARGET=`/`TARGET_ARCH=` are completely
inert without FreeBSD's base-system `Makefile.inc1`/`buildworld`
machinery, which a standalone project doesn't have.

Follow-up investigation across the whole BSD-make family (FreeBSD's
`Makefile.inc1`, NetBSD's `bsd.own.mk` + `build.sh`, and the generic
portable `mk-bmake` files) found the same pattern everywhere: real
cross-compilation always happens via an **external orchestration layer**
outside `bsd.prog.mk`/`bsd.lib.mk` themselves. `MACHINE`/`MACHINE_ARCH`
(NetBSD) and `TARGET`/`TARGET_ARCH` (FreeBSD) are used as **data** for
architecture-conditional branching inside `.mk` files, never as a
trigger that auto-selects a compiler binary. The actual compiler
selection is done by an external wrapper (`build.sh`, `Makefile.inc1`)
that builds/locates a real cross-toolchain and passes `CC=<path>`
explicitly.

**Design consequence** (recorded): `mk.toolchain.<name>.mk` must itself
map `(TARGET, TARGET_ARCH, TOOLCHAIN)` → concrete `CC`/`CXX`/`LD`/`AR`/
`AS` paths (a naming-convention/lookup-table it owns), the same way
`build.sh`/`Makefile.inc1` do for their own base-system builds, just
scoped to the phase-1 target set. `TARGET`/`TARGET_ARCH` remain valid as
plain data variables elsewhere.

*(`REQ-target-arch-toolchain-selection-is-custom-req`,
`OBS-validation-cross-compile-is-external-orchestration-everywhere`,
`REQ-toolchain-mk-must-set-explicit-cc-paths-req`)*

### 1.2 — `bsd.lib.mk` shared-library toggle

**Result: risk CONFIRMED, design corrected.**
Built `LIB=greet SRCS=greet.c SHLIB_MAJOR=1` with **no** `LIB_SHARED` set
at all. Result: **both** `libgreet.a` (static) and `libgreet.so.1`
(shared, versioned, with the `libgreet.so → libgreet.so.1` symlink
chain) were produced simultaneously. Source inspection confirms:
`defined(LIB)` alone unconditionally builds the static archive;
`defined(SHLIB_NAME)` (itself gated on `defined(SHLIB_MAJOR)`)
*additionally* triggers the shared build. There is no `LIB_SHARED=
YES|NO` toggle anywhere in `bsd.lib.mk`, and no discovered way to
suppress the static `.a` byproduct while keeping only the shared `.so`.

**Design consequence** (recorded): `LIB_SHARED=` is reclassified from
"reused native" to "new, project-specific." `mk.lib.mk` must auto-derive
a `SHLIB_MAJOR` default when `LIB_SHARED=YES` and none was set
explicitly, for the shared build to actually fire. Whether the static
`.a` byproduct is acceptable to always ship alongside a "shared-only"
module, or needs active suppression, is **still an open design
decision** — not resolved by this finding.

*(`OBS-validation-lib-shared-does-not-exist-natively`,
`REQ-lib-shared-is-new-not-reused-req`)*

### 1.3 — `SHLIB_MAJOR`/`SHLIB_MINOR` and `-MD` dependency wiring on macOS (MacPorts `bsdmake`)

**Result: NOT TESTED — no macOS/MacPorts environment available in this
sandbox.** This remains exactly as originally flagged: real risk,
unknown until tested on an actual Mac. Do not assume either way. Now
also covers a second question discovered during Tier 2.2: whether
MacPorts' `bsdmake` wires the compiler's own `-MD` flag into ordinary
compiles the way FreeBSD's own `bsd.sys.mk` does, or omits it the way
NetBSD's bundled set does — both are equally plausible outcomes and
this sandbox cannot distinguish between them
(`OBS-validation-md-wiring-is-freebsd-specific-not-family-wide`).

### 1.4 — Built-in `.y`/`.l` suffix rules

**Result: risk did NOT materialize — confirmed working, no changes
needed.**
A module with `SRCS=grammar.y lexer.l main.c` and zero explicit
suffix-rule declarations built and linked cleanly via built-in `.y.c`/
`.l.c` transformation rules, and the resulting binary ran correctly.
Bonus finding: the `.y.c` rule names output after the source file's own
basename (`grammar.y` → `grammar.c` + `grammar.h`), **not** the classic
`y.tab.c`/`y.tab.h` — this means multiple `.y` files in one module don't
collide, which is better than the naive assumption.

*(`OBS-validation-yacc-lex-suffix-rules-confirmed`)*

---

## Tier 2 — results

### 2.1 — `DEBUG_FLAGS` and optimization-flag naming

**Result: `DEBUG_FLAGS` half CONFIRMED working; `COPTFLAGS` guess was
WRONG, optimization variable still not identified.**
`bsd.debug.mk` genuinely appends `DEBUG_FLAGS` to `CFLAGS`/`CXXFLAGS`
when defined, and its presence/absence also toggles default automatic
symbol stripping (`STRIP?=-s` only fires when `DEBUG_FLAGS` is unset) —
a real, coherent, working mechanism. However, `COPTFLAGS` evaluated to
empty and is **not** what controls the default `-O2` seen in `CFLAGS`
output; that specific variable name was not conclusively identified in
this pass (not `CFLAGS` directly either — traced further upstream than
time allowed). **Still open**, to finish on a real FreeBSD box.

*(`OBS-validation-debug-flags-confirmed-native`)*

### 2.2 — `.depend`/`mkdep` mechanics

**Result: risk NOT what was assumed, and the investigation itself took
two wrong turns before landing on the right answer — worth reading in
full, not just the conclusion.**

**First pass**: ran `bmake depend` against real FreeBSD `share/mk` and
inspected the aggregate `.depend` file. It contained only a single
link-level line (`hello.full: /usr/lib/libc.a`) — no header dependency
tracking at all. `bsd.dep.mk` itself contains zero references to
`mkdep`; its `depend:` target logic is gated behind meta-mode
(`_meta_filemon`, kernel-level syscall tracing) or `MK_DIRDEPS_BUILD`,
both tied to FreeBSD's base-system build infrastructure. Concluded:
broken, needs custom wiring.

**Second pass, correcting the first**: that conclusion was wrong
because it tested the wrong mechanism. Every `cc` invocation during an
*ordinary* build already includes `-MD -MF.depend.<objname>
-MT<objname>` — `bsd.sys.mk` wires the **compiler's own native
dependency-generation flag** directly into every compile, with no
separate `make depend` step needed at all. Confirmed end-to-end:
touching a shared header and rebuilding correctly recompiled exactly
the two `.o` files that actually included it (one directly, one
transitively), then relinked. This looked like a clean, fully-native,
zero-effort win.

**Third pass, scoping the second correctly**: cross-checked the same
test against NetBSD's own *bundled* `mk-netbsd` set (the genuinely
portable lineage shipped inside the `bmake` package, as opposed to
FreeBSD's own base-system-specific `share/mk` fetched from GitHub).
Result: **zero** `-MD` wiring anywhere in `mk-netbsd`, plain `cc`
invocations with no dependency flags, and touching a header produced
**no rebuild at all**. So the `-MD` win is real, but it is a property
of FreeBSD's own actual `bsd.sys.mk` specifically — not a general
BSD-make-family guarantee. Since this project's phase-1 hosts are
**macOS (via MacPorts) and FreeBSD** — not NetBSD — the practically
relevant open question is now whether MacPorts' own `bsdmake` port
includes equivalent `-MD` wiring in its own `bsd.sys.mk`. That is
**unverified and untestable in this sandbox**, and now folds into the
same open gap as Tier 1.3 below (no macOS/MacPorts environment
available).

**Fallback, low-risk either way**: if MacPorts turns out to lack this
wiring, replicating it is straightforward — `mk.prog.mk`/`mk.lib.mk`
can add `-MD -MF<generated-path>` to `CFLAGS`/`CXXFLAGS` themselves and
`.include` the resulting per-object files, exactly what FreeBSD's
`bsd.sys.mk` already does. No `mkdep` tool invocation or more complex
mechanism is needed regardless of which way this resolves.

*(`OBS-validation-bsd-dep-mk-automatic-wiring-broken` — superseded
conclusion, kept for the record, not the current answer;
`OBS-validation-compiler-native-md-dependency-tracking-confirmed`;
`OBS-validation-md-wiring-is-freebsd-specific-not-family-wide`;
`REQ-md-dependency-tracking-freebsd-specific-req`)*

### 2.3 — `DESTDIR`/`PREFIX` install semantics

**Result: `DESTDIR` CONFIRMED working; `PREFIX` risk CONFIRMED and
corrected — it doesn't exist.**
`make install DESTDIR=/tmp/stage` correctly composed with `BINDIR` to
produce `/tmp/stage/bin/hello` — `DESTDIR` is genuinely bsd-make-native
and works exactly as expected. But grepping all of `bsd.own.mk`,
`bsd.prog.mk`, and `bsd.lib.mk` found **zero references to `PREFIX`** —
it isn't a native concept in this part of the build system at all. Real
FreeBSD base-system install uses hardcoded individual `*DIR` variables
(`BINDIR`, `LIBDIR`, etc.) directly with `DESTDIR` for staging, not a
single unifying `PREFIX` the way GNU autotools or MacPorts' own portfile
system do it.

Also found, confirmed on **both** the FreeBSD and NetBSD `mk` sets
independently: `install` does **not** auto-create missing `DESTDIR`
parent directories. The destination tree must already exist (install
without `-d` assumes a pre-populated hierarchy, traditionally via a
separate `mtree` step) — this is consistent across the whole family, not
a FreeBSD-specific quirk.

**Design consequence** (recorded): `PREFIX=` is reclassified from
"reused native" to "new, project-specific" — `mk.prog.mk`/`mk.lib.mk`
must derive `BINDIR`/`LIBDIR`/etc. from a project-level `PREFIX=`
themselves. The install/packaging mechanism must explicitly create
`bin`/`lib`/`share` subdirectories under `DESTDIR` before invoking
install.

*(`OBS-validation-destdir-native-prefix-is-not`,
`REQ-prefix-is-new-not-reused-req`)*

### 2.4 — Dynamic `SUBDIR` population for auto-discovery

**Result: CONFIRMED working, no caveats — the strongest positive finding
of the whole pass.**
`SUBDIR!= /bin/ls -d *.m 2>/dev/null` correctly populated `SUBDIR` from a
live directory scan, and `bsd.subdir.mk` correctly recursed into each
discovered directory in order. This directly de-risks the entire
auto-discovery philosophy the directory-layout design leans on.

Taken further than originally planned: since discovery alone isn't
enough (dependency *order* also matters — `bsd.subdir.mk` has no
topological-sort concept, it just processes whatever list it's given), a
full working prototype (`prototypes/gen-mod-order.sh`) was built and
tested:

1. Discover `.m` directories by scanning.
2. Query each one's `LIBS=` **in isolation** via
   `bmake -f <dir>/makefile -V LIBS` — confirmed this reads the variable
   without triggering a build.
3. Topologically sort (Kahn's algorithm), silently ignoring any `LIBS=`
   entry that isn't a locally-discovered module (an out-of-framework
   reference, e.g. a `PREREQS`-resolved framework library — confirmed
   with a real test: `LIBS=System` where `System` isn't a local module
   built successfully with no complaint).
4. Emit the sorted order to a generated `.mk` fragment
   (`SUBDIR=modA.m modB.m ...`), `.include`d before
   `.include <bsd.subdir.mk>`.

Tested and confirmed on a real 4-module dependency chain
(`A ← B ← C ← D`, with `C` depending on both `A` and `B`) — built in
exactly the correct order every time. A genuine cycle (`X ↔ Y`) was
confirmed to fail loudly with a clear diagnostic rather than hanging or
silently producing a broken order.

This closes what was, before this pass, the single biggest unwritten
piece of the whole design — turning `LIBS=`/`PREREQS=` dependency
declarations into an actual build order. The identical mechanism
generalizes directly to workspace-level framework ordering (query
`PREREQS=` instead of `LIBS=`, framework directories instead of `.m`
directories).

*(`OBS-validation-dynamic-subdir-confirmed-working`,
`DEC-dep-order-generation-mechanism-prototyped`,
`REQ-dep-order-generation-mechanism-req`,
`prototypes/gen-mod-order.sh`)*

---

## Tier 3 — results

Not tested this session. Both items remain as originally planned:

### 3.1 — `CFLAGS`/`CXXFLAGS`/`LDFLAGS`/`YFLAGS`/`LFLAGS` append behavior
Not tested. Low risk, quick to verify whenever convenient.

### 3.2 — `.include <file>` path resolution for project-local `mk.*.mk`
Not tested. Needed before writing real `mk.prog.mk`/`mk.lib.mk`/
`mk.framework.mk`/`mk.workspace.mk` files, since they need to find each
other via `.include <mk.*.mk>` from a project-controlled path, not just
`/usr/share/mk`.

---

## Bonus finding: man-page suppression anomaly (investigated, resolved as environment artifact)

Early in testing, neither `MK_MAN=no` nor `WITHOUT_MAN=yes` suppressed
`bsd.prog.mk`'s man-page sub-target when using the portable `bmake`
binary against the **fetched, sparse-checkout FreeBSD share/mk** (missing
surrounding infrastructure like `src.opts.mk`'s full option-registration
chain). Re-tested against NetBSD's own **self-consistent** bundled
`mk-netbsd` set: plain `MAN=` (empty) worked with zero fuss. Conclusion:
this was an artifact of mixing an unrelated `bmake` binary with an
incomplete FreeBSD checkout, not a real defect in the man-page-
suppression mechanism itself. Not a design concern.

---

## What's still genuinely open after this pass

1. **Tier 1.3** — macOS/MacPorts `bsdmake` Mach-O dylib support, AND
   whether MacPorts' `bsdmake` wires in `-MD` dependency tracking the
   way FreeBSD's own `share/mk` does. Needs a real Mac; nothing here
   substitutes for it.
2. **Tier 3.1/3.2** — Not tested, low-to-medium priority.
3. **Optimization-flag variable name** (part of 2.1) — `COPTFLAGS` ruled
   out, actual variable not identified.
4. **`LIB_SHARED=YES` static-archive byproduct** — is it acceptable, or
   does `mk.lib.mk` need custom suppression logic? Not decided.
5. **`mk.toolchain.<name>.mk`'s actual CC-path lookup table** — the
   *mechanism* is now clear (see 1.1 above), but the concrete table for
   the phase-1 target set hasn't been written.

## Suggested next step

Given the dependency-order mechanism (2.4) is now a solved, tested
problem, header-dependency tracking (2.2) is understood well enough to
design around either outcome on macOS, and the remaining Tier 1 risks
(1.1, 1.2) are both understood well enough to design around, the next
highest-value work is either (a) finishing Tier 1.3 on real hardware, or
(b) starting to write
`mk.prog.mk`/`mk.lib.mk`/`mk.framework.mk`/`mk.workspace.mk` for real,
now that every piece they depend on has either been confirmed or has a
concrete, tested fallback.
