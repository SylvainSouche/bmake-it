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
    │   ├── src/                              greet.c, grammar.y — auto-discovered (dot-files skipped)
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

On `win` the ABI is **read from the compiler**, not taken on trust,
because the omitted slot claims MSVC's runtime
(`REQ-win-abi-from-compiler-req`): `TOOLCHAIN=msvc` is `msvc` (`cl.exe`
has no `-dumpmachine`); otherwise `${CC} -dumpmachine` decides —
`*cygwin*`/`*cygnus*` → `cygwin` (Cygwin gcc says `x86_64-pc-cygwin`,
Cygwin clang `x86_64-pc-windows-cygnus`: POSIX output linked against
`cygwin1.dll`), `*mingw32*`/`*windows-gnu*` → `mingw`, `*windows-msvc*` →
`msvc`. So a `CC=` override is labelled by what it really is. An
unrecognized answer is an error naming it; an explicit `ABI=` that
contradicts the compiler fails the build quoting the compiler's answer.
The answer is cached in the environment per `CC`, so one build's nested
makes ask once. Until 2026-10-15 the slot was filled only from an
explicit `ABI=`, so Cygwin and mingw output were both labelled as
MSVC's `win-amd64`.

**mingw-w64 output** (`REQ-mingw-on-cygwin-req`) is produced when
cross-compiling to `win` with a non-MSVC toolchain (tier 2), and on a
Cygwin host for its own arch with `ABI=mingw`:

| Toolchain | Compiler | Key |
|---|---|---|
| `gcc` | `<triple>-gcc`/`-g++`, with `<triple>-ar`/`-ranlib` | `win-amd64-gcc-mingw` |
| `llvm` | `clang --target=<triple>`; `--sysroot` only from `BMK_MINGW_SYSROOT=`, otherwise clang locates an installed `<triple>-gcc`'s headers, CRT and libgcc itself; linked with `ld.lld` if installed, else `<triple>-ld` | `win-amd64-mingw` |

An explicit Cygwin sysroot (`/usr/x86_64-w64-mingw32/sys-root/mingw`)
was tested and loses the C++ headers and libgcc, which live outside it
under `/usr/lib/gcc/x86_64-w64-mingw32/<ver>` — hence no default
`--sysroot`. A missing compiler, sysroot or linker is an error naming
the packages that provide them (`REQ-mingw-sysroot-error-actionable-req-v2`).
Verified on Cygwin with the example workspace: both routes build a
PE32+ `hello.exe` and DLL with no `cygwin1.dll` dependency, which run.

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
| `obj/*.d` | Per-source header dependency file (gcc/clang `-MMD -MP`), `.include`d automatically on the next build; not produced under `TOOLCHAIN=msvc` | `REQ-header-dependency-tracking-req` |
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

## Optional directories, not shown above

- **`mk/`** at workspace, framework, or module level — local-mk
  customization hooks (`pre.mk`/`local.mk` and their `${TOOLCHAIN}`/
  `${TARGET}` variants), cascading outward-in. See
  `50-makefile-macros.md`.
- **`tests/`** at module level — `TESTS_CXX=`/`TESTS_C=`/`TESTS_SH=`
  sources for `bmake test`. See `80-unit-testing.md`.
- **`docs/`** — `bmake docs` output (Doxygen HTML, tag files); not
  source, not committed. See `70-documentation-generation.md`.
- **`build/<KEY>/runs/<RUN_ID>/build.log`**, **`.../build.failed`** — at
  module and framework level, always written by a workspace/framework
  `all` (not module-only builds); a rolling log and a failure marker for
  that one run, with `runs/latest/` always kept as a copy of the newest
  — not source, not committed. See `40-cli-reference.md`.
- **`build-report/<RUN_ID>/<KEY>/`**, **`test-report/<RUN_ID>/<KEY>/`**
  at workspace level (each with a `latest/<KEY>/` copy) — the
  `REPORT=yes` dashboards, one per target key per run so two keys built
  under the same `RUN_ID` don't collide; not source, not committed. See
  `40-cli-reference.md`.
