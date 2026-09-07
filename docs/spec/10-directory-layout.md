# Bmake It — 10: Directory Layout

Status: DRAFT, synthesized from confirmed `project-model/req/` objects.

## Worked example

Two frameworks, `System` and `Hello` (`Hello` declares `PREREQS=System`).
`Hello` has an executable module `hello.m` and a shared-library module
`libgreet.m` that `hello.m` links against. `libgreet.m` also generates one
header via yacc and promotes it to public. See `20-headers-and-linking.md`
for why the header/library resolution works the way it does here.

```
myworkspace/                                  workspace root (REQ-workspace-is-set-of-frameworks)
├── makefile                                  .include <mk.workspace.mk>              (REQ-uniform-makefile-filename-req)
│                                              PARENT_WS=/abs/path/ws1 /abs/path/ws2   (REQ-workspace-parent-macro-absolute-req)
├── build/
│   └── macos-arm64/                          workspace-level consolidated output for one target
│       ├── bin/                              hello
│       ├── lib/                              libgreet.dylib
│       └── share/                            consolidated resources, from frameworks only
│       (no include/ here — never consulted at compile time, only via distrib/ at packaging)
├── distrib/
│   └── macos-arm64/                          packaging staging area, same target-key scheme as
│       └── {bin,lib,share}/                  build/, populated by `make install DESTDIR=distrib/<KEY>`
│                                              as the first step of any binary-package target
│                                              (REQ-distrib-dir-for-packaging-staging-req,
│                                               REQ-packaging-invokes-install-into-distrib-req)
│
├── System/                                   framework, auto-discovered by scanning workspace root
│   ├── makefile                              .include <mk.framework.mk>; PREREQS=  (empty, but MANDATORY —
│   │                                          REQ-prereqs-mandatory-even-empty-req — this presence is also
│   │                                          the signal that makes System auto-discoverable as a framework,
│   │                                          REQ-framework-discovery-signal-req)
│   ├── include/                              System's public headers (hand-written, source)
│   ├── local/include/                        visible to all of System's own modules
│   ├── share/{common,macos,freebsd_amd64}/
│   ├── build/macos-arm64/{bin,lib,share}/    System's consolidated outputs
│   └── (System's own modules — omitted)
│
└── Hello/                                    framework, PREREQS=System
    ├── makefile                              .include <mk.framework.mk>; PREREQS=System
    │                                          (ordered; misordering is NOT validated — surfaces only
    │                                           as an ordinary header-not-found compile error)
    ├── include/                              Hello's public headers
    ├── local/include/                        visible to all of Hello's own modules
    ├── share/{common,macos,freebsd_amd64}/
    ├── build/
    │   └── macos-arm64/
    │       ├── bin/  lib/  share/            copied up from modules
    │       └── include/                      GENERATED-ONLY, promoted via INCL=
    │
    ├── libgreet.m/                           module dir, .m suffix, auto-discovered by scanning
    │   │                                      Hello/ for *.m subdirectories
    │   ├── makefile                          .include <mk.lib.mk>
    │   │                                      LIB=greet          (defaults to dir name if omitted)
    │   │                                      LIB_SHARED=YES     (default; =NO → static/archive)
    │   │                                      SHLIB_MAJOR=1      (→ libgreet.so.1 + symlink on FreeBSD/Linux;
    │   │                                                            → libgreet.1.dylib + symlink AND
    │   │                                                            -compatibility_version/-current_version
    │   │                                                            on macOS)
    │   │                                      LIBS=              (link-time only, none needed here)
    │   │                                      INCL=grammar.h     (promotes this ONE generated header)
    │   ├── include/                          module-private hand-written headers
    │   ├── src/                              greet.c, grammar.y — auto-discovered
    │   ├── share/{common,macos,freebsd_amd64}/
    │   └── build/
    │       └── macos-arm64/
    │           ├── obj/                      greet.o, grammar.o
    │           ├── lib/                      libgreet.so.1 (or libgreet.1.dylib), before copy-up
    │           ├── include/                  grammar.h (generated), PRIVATE by default
    │           └── share/
    │
    └── hello.m/                              module dir, executable
        ├── makefile                          .include <mk.prog.mk>
        │                                      PROG=hello         (defaults to dir name)
        │                                      LIBS=greet         (link-time only; hello.m can use
        │                                                           greet's grammar.h ONLY because Hello's
        │                                                           own PREREQS makes it visible, not
        │                                                           because of this LIBS entry)
        ├── src/                              main.c
        └── build/
            └── macos-arm64/
                ├── obj/                      main.o
                └── bin/                      hello, before copy-up
```

## Target key

`<os>-<arch>[-<toolchain>][-<abi>]`, each bracketed segment omitted when
it equals that OS's default (`REQ-target-key-omit-defaults-req`):

| Segment | Default (omitted) | Shown when non-default |
|---|---|---|
| toolchain | `llvm` | `gcc` |
| ABI/libc (only where >1 exists) | `msvc` (win); `glibc` (linux); n/a for macos/freebsd | `mingw`, `cygwin` (win); `musl` (linux) |

Phase-1 concrete keys: `macos-arm64`, `macos-arm64-gcc`, `freebsd-amd64`,
`freebsd-amd64-gcc`. Architecture labels use each platform's native name
(`arm64`, `amd64` — not `x64`/`x86_64`), matching `uname -m/-p`.
`$OS_ARCH` never encodes build variant (debug/release) — those share one
target's directory and overwrite each other on rebuild
(`REQ-variant-out-of-scope-for-dirtree`).

Everything under `build/` (and `distrib/`) is keyed this way at every
level, which is what lets all four phase-1 targets coexist in the same
source tree without collision. `build/` is disposable — deletable and
fully regenerable from source.

## Naming conventions

| Thing | Convention | Source |
|---|---|---|
| Module directory | `NAME.m`, auto-discovered; case-sensitivity follows host filesystem | `REQ-module-dir-naming-convention`, `REQ-module-name-case-sensitivity-req` |
| Framework directory | plain name, auto-discovered via `makefile` + mandatory `PREREQS=` | `REQ-framework-discovery-signal-req` |
| Makefile filename (every level) | `makefile` | `REQ-uniform-makefile-filename-req` |
| Build output root | `build/<os>-<arch>[-<toolchain>][-<abi>]/` | `REQ-build-output-tree-structure` |
| Build output subdirs | `obj/` (module only), `bin/`, `lib/`, `share/` at every level; `include/` (generated only, module+framework) | `REQ-build-output-mirrors-prefix-layout`, `REQ-module-level-build-subdirs-req` |
| Packaging staging root | `distrib/<KEY>/{bin,lib,share}/`, same key scheme as `build/` | `REQ-distrib-dir-for-packaging-staging-req` |
| Program/library naming | `NAME`/`libNAME.*`; versioned via `SHLIB_MAJOR`/`SHLIB_MINOR`, platform-native emission | `REQ-shlib-major-minor-cross-platform-emission-req` |
| Resource source | `share/{common,<os>,<os>_<arch>}/`, 3-layer overlay copy | `REQ-share-dir-fallback-hierarchy`, `REQ-share-overlay-copy-order` |

`build/<KEY>/{bin,lib,share}` deliberately mirrors a real install-prefix
layout (`/usr/local/{bin,lib,share}`, `/opt/local/{bin,lib,share}` under
MacPorts) — not an arbitrary convenience structure
(`REQ-build-output-mirrors-prefix-layout`). A macOS `.app` bundle would
need a structurally different layout (`Contents/MacOS`, `Contents/
Frameworks`, `Contents/Resources`) — deferred, not designed
(`REQ-app-bundle-deferred-req`).

Resource staging (`share/`) is a **layered overlay copy**, not a
pick-one-directory selection: `common/` copies first, then `<os>/` on top
(overwriting same-named files), then `<os>_<arch>/` on top of that. Files
unique to any layer survive; files present at multiple layers end up as
the most specific version (`REQ-share-overlay-copy-order`). Unlike the
build-output target key, the resource fallback key is **OS+arch only** —
toolchain never affects resource variant selection.
