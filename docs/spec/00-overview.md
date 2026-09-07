# Bmake It — 00: Overview & Scope

Status: DRAFT, synthesized from confirmed `project-model/req/` objects.
Not itself a project-model object. Every claim cites the REQ/CON/NREQ
alias(es) it comes from.

## What this is

A BSD-make-based, cross-platform build system for C/C++ (plus lex/yacc
grammar sources), designed to mimic the conceptual model of Dassault
Systèmes' RADE/`mkmk` — workspaces, frameworks, modules, prerequisites —
while diverging deliberately from `mkmk`'s specific mechanisms wherever a
simpler or more BSD-make-idiomatic approach fits better
(`CON-use-bsdmake`).

Two deliberate divergences from real `mkmk`, rejected outright rather
than left open:

- **No dedicated identity-card special file** for prereqs — they live in
  the ordinary framework `makefile` instead (`NREQ-no-identitycard-special-file`).
- **No four-level RADE header hierarchy** (Public/Protected/Private/
  Local) — this project uses a different three-level scheme instead
  (`NREQ-no-four-level-header-visibility`).
- **No `mkGetPreq`/`mkCopyPreq`-style commands** — prereq resolution is
  purely dynamic search over the workspace's own declared parent list,
  no static-copy mode, no dedicated setup command (`NREQ-no-copy-preq-commands`).
- **No workspace-level `share/` source** — only modules and frameworks
  carry resources (`NREQ-no-workspace-level-share-source`).

## Domain model

- **Workspace** (`REQ-workspace-is-set-of-frameworks`): a set of
  frameworks. May declare an ordered list of parent workspaces
  (`PARENT_WS=`, absolute paths only — `REQ-workspace-parent-macro-absolute-req`)
  that the build searches, in order, for anything not found locally
  (`REQ-workspace-parent-search-order`) — purely dynamic, no copy mode
  (`DEC-prereq-access-dynamic-only` / `NREQ-no-copy-preq-commands`).
- **Framework** (`REQ-framework-contains-modules`): contains one or more
  modules, exposes public headers, and declares its prerequisite
  frameworks via `PREREQS=` (`REQ-framework-prereqs-macro-req`) —
  mandatory even when empty (`REQ-prereqs-mandatory-even-empty-req`),
  since its presence doubles as the auto-discovery signal
  (`REQ-framework-discovery-signal-req`).
- **Module** (`REQ-module-is-basic-link-unit`): the basic link unit —
  produces an executable, static library, or shared library. Directory
  named `NAME.m` (`REQ-module-dir-naming-convention`), auto-discovered by
  scanning (`REQ-modules-and-frameworks-auto-discovered-req`).
- **Resource files** (`REQ-resource-file-model`): non-source runtime data,
  carried by both modules and frameworks, staged via a `share/` overlay
  (see `20-headers-and-linking.md` is NOT where this lives — see
  `10-directory-layout.md`).

## Language & platform scope

- **Languages**: C, C++, and lex/yacc grammar sources (compiled to
  C/C++). Java, Fortran, IDL, Express — out of scope for now
  (`REQ-supported-languages`).
- **Hosts**: macOS (MacPorts), Linux, *BSD (`CON-cross-platform-targets`),
  plus Cygwin/WSL treated as *NIX-like build hosts, no native MSVC
  requirement (`REQ-windows-hosts-cygwin-wsl`). WSL is really just Linux;
  `win`-target output is reachable via cross-compilation (mingw-w64-class
  toolchain) from any capable host, not exclusively from Cygwin
  (`REQ-win-target-via-cross-toolchain-req`).
- **Default toolchain**: LLVM/clang; legacy OS-native gcc is the
  alternative (`REQ-default-toolchain-llvm`). Default build target is the
  host's own OS/arch (`REQ-default-build-host-os-arch`).
- **Scope is userland only** — no kernel modules/drivers, no Darwin/XNU
  kernel development (`REQ-userland-only-scope`).

## Phase 1 concrete targets

Exactly four (`REQ-phase1-concrete-targets`):

- `macos-arm64` (llvm, default) / `macos-arm64-gcc`
- `freebsd-amd64` (llvm, default) / `freebsd-amd64-gcc`

macOS output is plain command-line tools/libraries — `.app` bundle output
is deferred (`REQ-app-bundle-deferred-req`).

## Deferred / out of scope (not designed, not blocking)

- OpenBSD, NetBSD, per-distro Linux labeling (`REQ-os-label-set-req`)
- Kernel modules/drivers, Darwin/XNU kernel development
  (`REQ-userland-only-scope`)
- macOS `.app` bundle output (`REQ-app-bundle-deferred-req`)
- `win` target ABI details — mingw vs. Cygwin vs. MSVC, exact toolchain/
  ABI naming (`REQ-win-target-via-cross-toolchain-req`)
- Linux libc beyond the glibc default (musl always explicit —
  `REQ-linux-libc-default-glibc-req`)
- Java, Fortran, IDL, Express (`REQ-supported-languages`)
- `make port`'s actual generation mechanism (`REQ-make-port-deferred-req`
  — its *category*, source-recipe not binary package, is settled:
  `REQ-port-target-is-source-recipe-not-binary-package-req`)
- Test infrastructure, documentation generation, package versioning/
  maintainer metadata (`REQ-tests-docs-versioning-deferred-req`)
- Cycle detection across `PREREQS`/`LIBS` dependency graphs — explicitly
  undefined behavior for now (`REQ-prereqs-misorder-no-validation-req`)
- Cross-filesystem `make install` (`REQ-install-requires-prebuilt-target-req`)
- `mkGetPreq`/`mkCopyPreq`-style commands, identity-card file, 4-level
  header visibility — **rejected outright**, not deferred (see NREQs
  above)

See `10-directory-layout.md` for the concrete tree, `20-headers-and-linking.md`
for header/library resolution, `30-build-sequence.md` for build ordering,
`40-cli-reference.md` for `make` usage, `50-makefile-macros.md` for the
full macro reference.
