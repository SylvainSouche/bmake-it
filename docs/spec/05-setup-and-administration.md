# Bmake It — 05: Setup and Administration

Status: **DRAFT, specified, not implemented** beyond what "What exists today"
lists. Items are **decided** (design discussion 2026-10-14,
`environment-management-levels-dec`, `config-makefile-dec`,
`working-and-deployed-config-dec`; the earlier proposals were validated) or
carry an explicit **Open** question.

## Scope

How Bmake It is installed and configured, and how the environments it builds
and tests in — particularly for cross-platform work — are set up and kept. It
covers three levels of environment management, where an environment runs, and
what each placement needs. It does not cover how a *project* declares its own
dependencies (`25-imported-libraries.md`, `27-prerequisite-software.md`) or
which targets a module is built for (`28-platform-toolchain-constraints.md`).

## What exists today

Facts about the current code, so the rest can be read as a delta.

- **Finding Bmake It.** `MAKESYSPATH=<bmake-it>/mk:<system mk>` (or
  `BMK_MKDIR=`), set per command or through `scripts/install-env.sh`, which
  edits a shell rc file. There is no per-project way to point at it.
- **Host tool prefixes.** One `mk/mk.paths.<os>.mk` per host OS names where
  that platform's compilers live (MacPorts, Homebrew, pkgsrc, Nix, ...).
- **Cross-compiling.** For a target different from the host, llvm needs one
  variable per target OS naming a sysroot — `BMK_LINUX_SYSROOT`,
  `BMK_FREEBSD_SYSROOT`, `BMK_NETBSD_SYSROOT`, `BMK_MACOS_SYSROOT` — and
  builds `--target=<arch>-<os> --sysroot=<dir> -fuse-ld=lld`. A missing one is
  an error. gcc never cross-compiles. Nothing provisions or remembers a
  sysroot: the error message points at `scripts/prep-*-sysroot.sh`, **which do
  not exist**; the scripts that build sysroots are in `tests/harness/fetch/`
  and are written for the harness.
- **Hooks.** `mk/pre.mk`, `pre.<os>.mk`, `local.mk`, ... in `PARENT_WS`, the
  workspace, the framework and the module, outer to inner. No machine-wide or
  per-user level.
- **The harness** (`tests/harness`) keeps VM images, container images and
  sysroots in a cache under the user's home for Bmake It's own test matrix. It
  is not part of the product and does not serve projects built with Bmake It.

## Three levels of environment management (decided)

| Level | Who | Where the environment comes from | Stored |
|---|---|---|---|
| **User** | one person | the user declares a distro and packages; the tooling downloads and builds the matching environment locally | the user's cache |
| **Computer or team** | an administrator | built locally once by the administrator, or copied from another machine's cache | a machine-wide cache, used by every user of the machine |
| **Enterprise** | an organisation | builds are configured against a managed OS/software baseline: a preset OS and toolchain, or one built by the same tooling, whose advantage is a fully reproducible process | a managed store |

**The first implementation target is the computer or team level**
(`computer-level-environment-store-req`): build and store locally for every
user of the machine. The other two levels reuse its mechanism later.

## Placements and what each needs (decided: this must be documented)

An environment can run **natively**, in a **local virtual** environment (a
container or a VM), on a **remote** machine, or in a **virtual environment on a
remote host** (`setup-documents-placements-req`). What each needs:

| Placement | Needs |
|---|---|
| Cross-compiling | the llvm toolchain, `lld`, and a **sysroot** of the target (its headers, libraries, startup files, dynamic linker) — see below |
| Local virtual | a container runtime (Docker, Colima, Podman) for Linux targets; a hypervisor for others (QEMU with hardware acceleration for same-architecture guests, tart/Virtualization.framework for macOS guests); disk space for the images |
| Remote | ssh access to the machine, the toolchain already on it, and a way to move the sources there and the results back |
| Remote virtual | both of the above: a remote host that can run the container or VM |

### What a sysroot contains

A directory holding a copy of the *target's* system files, so the compiler
never uses the host's. By target: **Linux** — `usr/include`,
`usr/lib/<multiarch>`, `lib/<multiarch>`, plus `usr/lib/gcc/<arch>/<ver>/`
(the startup objects and `libgcc`) and the dynamic linker copied as a real file;
**FreeBSD** — `usr/include`, `usr/lib`, `lib` from a release's `base.txz`;
**NetBSD** — the same plus `libexec/ld.elf_so` at exactly that path;
**macOS** — an `MacOSX.sdk`. A Linux sysroot is kept as a tar and extracted
inside a container, because a case-insensitive filesystem (macOS's default)
corrupts kernel headers that differ only by case.

### What cannot be automated

- **macOS guests** run only on Apple hardware, under Apple's licence; the SDK
  may be extracted from a local Xcode install but not redistributed.
- **Windows** guests need a licence; a Windows **arm64** VM is not automatable.
- A guest of the **same architecture** as the host is fast; another
  architecture is emulated and slow, and some emulated BSD guests do not boot
  at all today.

These targets can be described and verified but not built unattended.

## The configuration makefile (decided)

(`config-makefile-dec`, `bmakeit-config-makefile-req`,
`config-locations-in-config-makefile-req`)

Administration is a makefile, like everything else in Bmake It. A
**configuration directory** holds a `makefile` that includes the role file
`mk.bmakeit.mk`, exactly as a module's makefile includes `mk.prog.mk`:

```makefile
# <configuration directory>/makefile
CACHE_DIR = /var/cache/bmake-it
BMK_LINUX_SYSROOT = ${CACHE_DIR}/sysroots/linux-arm64
.include <mk.bmakeit.mk>
```

- **It is where every location is set.** The cache directory, and any or all
  other configuration variables naming where things used and needed live —
  images, sysroots, tool prefixes — are variables in this makefile. There is
  no default location outside it, so nothing is hidden: to find where
  something is, read this file.
- **`mk.bmakeit.mk` defines the administrative targets** an administrator runs
  from that directory: list what is present and what is not, fetch, build and
  delete, and check checksums. Names proposed, not fixed: `status`, `fetch`,
  `build`, `delete`, `prune`, `verify`, `copy-from` (copy entries from another
  machine's cache over ssh/rsync, then verify them), `config` (print which
  configuration files were read, in order) and `help`.
- **One role, two scopes.** The same makefile serves the machine (site) scope
  and the user scope; the scope is just where the makefile sits, and the
  variables in it say where its cache is.
- **Each environment is a file**, so make's own "present and current" logic
  does the work, and the declarations are ordinary macros beside the targets.

A project build never reads this makefile: it reads the **deployed set**
described next.

## Working set and deployed set (decided)

(`working-and-deployed-config-dec`, `deployed-config-read-by-builds-req`)

Administrative configuration exists in two forms.

- **The local working set** is the configuration makefile and the cache being
  built up beside it. The administrator edits it and exercises it with the
  administrative targets; it may be incomplete or in flux.
- **The deployed configuration set** is what the Bmake It machinery reads. A
  project build, a cross-compile, `bmake run` and the rest read the deployed
  set **only**, never the working makefile. A build therefore cannot see a
  half-edited configuration, and never loads the administrative targets —
  which is how a build gets `BMK_LINUX_SYSROOT` and the other locations.

**Deploy mechanics** (decided: `config-deploy-mechanics-dec`,
`config-deploy-req`, `deployed-set-format-and-distribution-req`): a `deploy`
target runs verification first (checksums; each image still matches its
declaration) and only then replaces the deployed set **atomically**, keeping the
previous one for `rollback`; `diff` shows working against deployed, and `status`
shows both. The deployed set is plain variable files readable by bmake —
locations, sysroots, tool prefixes, and the environments with their hashes and
checksums — in a place builds can read and users cannot write. A team or an
enterprise distributes the **deployed set**, copying it together with the cache
entries it names, rather than the working makefile; that is also what makes a
managed baseline reproducible.
Open: where the deployed set lives, its exact format, and how a site and a user
deployed set combine.

## Configuration levels (decided; open sub-questions marked)

Two levels outside any project, read by the existing hook cascade, outermost
first: **site** (the administrator: `<prefix>/etc/bmake-it/mk/` following the
install prefix, as MacPorts and pkgsrc do, or a fixed `/etc/bmake-it/mk/`),
then **user** (`${XDG_CONFIG_HOME:-~/.config}/bmake-it/mk/`), then `PARENT_WS`,
workspace, framework and module. An inner level overrides an outer one, so a
project can always override a machine setting. `BMK_CONFIG_DIRS` replaces or
extends the list, because CI and containers cannot write under `/etc`. A
command prints which files were read, in order, so the effective setup is never
a guess. These two levels are the *locations* of configuration directories;
what is set in them, and the cache location in particular, is set in the
configuration makefile above, once per machine rather than in every project.
Open: install prefix versus fixed directory; the Windows location
(`config-levels-site-user-cand`).

## Declaration, cache and reproducibility (decided; open sub-question marked)

An environment is described by a **declaration** (distro and version, packages,
toolchain). The built image is named by the **hash of its declaration**, so the
same declaration always reuses its image and a changed package list rebuilds
it — replacing the harness's "the file exists" cache, which records no version.
Lookup is **tiered**: the machine's cache, then a peer or team cache (copying an
image from another machine is safe because the name is the hash, and it can be
checked against its declaration afterwards), then a local build. A **lockfile**
of resolved versions and checksums (distro snapshot, each package, the
toolchain build) is what makes the enterprise build fully reproducible; without
it "Debian trixie plus these packages" means different things a month apart.
Open: whether the lockfile is in the first design
(`environment-declaration-and-cache-cand`).

## Open

- Remote transport (ssh plus rsync first), who may write a shared cache, and,
  for a managed baseline, whether drift from it stops the build or only warns
  (`environment-remote-and-verification-cand`).
- The enterprise level: how a managed baseline is described and verified.
- The user level: declaring a distro and packages in a project.

## Known gaps in today's tooling

In the harness that tests Bmake It itself (not in the product), as of
2026-10-20. The gaps found while writing this chapter — the ignored
`tests/harness/build/` directory, the hardcoded `~/.bmk-cache`, the stale
FreeBSD/NetBSD image URLs, the unwired VM platforms — are closed: the scripts
are tracked, `BMK_CACHE` and `BMK_RUN` set where things live, `vm.sh` fetches,
provisions and boots the guests, and `matrix.sh` runs every cell of
`matrix.tsv` and says why a cell cannot run. Still open:

- **amd64 BSD guests.** FreeBSD and NetBSD amd64 stall under QEMU's software
  emulation on an arm64 host, so their native cells and the run half of their
  cross cells are *blocked*, with that reason in `matrix.tsv`; the cross
  *builds* for them pass.
- **NetBSD 11.x** panics on Apple silicon under hvf (`unknown CPU ... Illegal
  Instruction`), so the arm64 guest is pinned to NetBSD 10.2.
- **Cross to macOS** builds but does not link from the Debian 13 container:
  its lld (LLVM 19) cannot read the current macOS SDK's TAPI stubs. A newer
  LLVM in the image, or an older SDK, closes it.
- **Windows**: no guest and no sysroot recipe yet (the cell is a *gap*). The
  EWDK (MSVC build tools, verified) is cached for when there is one; a Windows
  arm64 guest cannot be built unattended.
- **A cross sysroot must hold the target's prerequisites** (found building
  OpenRider for NetBSD and for Linux; `cross-sysroot-os-only-obs`,
  `cross-sysroot-with-prerequisites-cand`). *Lookup, done*
  (`cross-import-from-sysroot-dec`): every cross build -- another OS, or another
  architecture of the same OS -- runs `pkg-config` for `IMPORT=pkg:` and
  `REQUIRES=` with `PKG_CONFIG_SYSROOT_DIR=<sysroot>` and `PKG_CONFIG_LIBDIR`
  limited to the target's own `.pc` directories there (Linux
  `usr/lib/<multiarch>/pkgconfig`, FreeBSD `usr/local/libdata/pkgconfig` and
  `usr/libdata/pkgconfig`, NetBSD `usr/pkg/lib/pkgconfig` and
  `usr/X11R7/lib/pkgconfig`, `usr/lib` and `usr/share` everywhere), never the
  host's. *Content, Linux done*: `tests/harness/fetch/build-sysroot-linux.sh
  <arch> <tar> <image>` makes the sysroot from an image that has the `-dev`
  packages installed. *Still open*: FreeBSD and NetBSD sysroots with
  `/usr/local` and `/usr/pkg` (`vm.sh sysroot` carries only `usr/include`,
  `usr/lib` and `lib`), and declaring the package list once (the configuration
  makefile below).
- **The macOS guest** is a tart VM provisioned by hand once
  (`provision-macos-vm.sh`, `provision/packages-macos.sh`); it has no
  layers/reset like the QEMU guests.
- **Emulated Linux platforms** (amd64 on an arm64 host) flake under load: a
  case that passes only on a retry is reported as flaky, never hidden.
- **Big stores on an exFAT drive.** The cache (`BMK_CACHE`) holds only regular
  files, so it can live on an exFAT external drive. exFAT has no sparse files,
  symlinks or clones, and such a drive may be slow (the maintainer's writes at
  about 10 MB/s): an APFS sparse image on it was tried and measured at 1.5 MB/s,
  so anything a VM *runs from* (tart's macOS VM, container storage) stays on the
  fast local disk, cold data goes to the drive as one compressed archive, and
  data a registry can serve again (tart's cached base images) is not stored
  twice.
- Container images keep the `bmk/*` tags; a machine that built them under the
  earlier `rade-bmake/*` tags needs `docker tag` once (see `tests/README.md`).
