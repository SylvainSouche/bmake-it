# Version history

The current version is in [`VERSION`](VERSION). This file says what each
version holds, and has one row for each push to `main` or merged pull request
that changed what Bmake It does or how far it can be relied on.

## How versions are numbered

Versions read `0.RUN.LANDING`.

- **`RUN`** goes up when a new run of related work starts. It does not by
  itself mean a breaking change: 0.6.7 and 0.6.8 change existing behaviour.
- **`LANDING`** goes up for each later landing on `main` in that run, whether
  it adds a feature or hardens what exists.
- **A landing that changes only documentation or the project model** gets no
  number and stays on the version before it.
- **Bmake It stays at 0.x** until CI covers what it claims to support. MSVC,
  macOS, BSD guests and cross builds are not in CI yet.

Each new row gets a matching `v<version>` tag on its commit.

## Reconstructed history

Versions 0.3.0 to 0.8.2 were worked out afterwards, on 2026-11-05, from the
history of `main`. They were not releases at the time, and `VERSION` still read
0.2.0 in all of those commits. Dates are UTC, from GitHub's record of when each
landing reached `main`.

### 0.8: stricter errors and cleanup

| Version | Date | Commit | Landing | What changed |
|---|---|---|---|---|
| 0.8.2 | 2026-11-05 | `b132919` | push | Case 114 needs no cross compiler; the CI report names the failed case |
| 0.8.1 | 2026-11-04 | `6944c65` | push | Temporary files and objects do not outlive their use |
| 0.8.0 | 2026-11-04 | `bb2d7a5` | PR #21 | `mk.common.mk` can be included first; a setting changed too late is an error |

### 0.7: Windows, native tests, CI and manual pages

| Version | Date | Commit | Landing | What changed |
|---|---|---|---|---|
| 0.7.8 | 2026-11-03 | `442c428` | push | Values are passed down a build instead of being asked for again |
| 0.7.7 | 2026-11-03 | `6ce6b4f` | push | GitHub Actions, manual pages, `DELAYLOAD`, imported DLL staging |
| 0.7.6 | 2026-11-02 | `d9e3966` | push | `TOOLCHAIN=llvm ABI=msvc`, `TEST_LINK=`, `NATIVE_CURDIR`, OpenRider's Windows fixes |
| 0.7.5 | 2026-10-31 | `5184452` | push | The ATF Bmake It carries: native Windows tests, `BMK_ATF=bundled`, self-test |
| 0.7.4 | 2026-10-29 | `299cf78` | push | A failed test module no longer blocks copy-up; ATF in the preflight |
| 0.7.3 | 2026-10-29 | `7b05d93` | push | One preflight list of what is missing; explained `run` and ATF failures; manual v2 |
| 0.7.2 | 2026-10-28 | `d3f15fe` | push | `bmake test` on Cygwin; `install-env.sh` takes a make that is bmake; BSD host cells |
| 0.7.1 | 2026-10-27 | `990359a` | push | Import staging re-runs when what it staged has gone |
| 0.7.0 | 2026-10-27 | `0081cf1` | push | MSVC from an EWDK; whole suite on MSVC and mingw-w64; QEMU guests on a Windows host |

### 0.6: mingw-w64 and cross-platform

| Version | Date | Commit | Landing | What changed |
|---|---|---|---|---|
| 0.6.9 | 2026-10-26 | `a10ef88` | push | Leftover module directories after `git switch`; `clean` leaves no empty `build/` |
| 0.6.8 | 2026-10-24 | `457704b` | PR #20 | Cross builds find system libraries in the target's sysroot (behaviour change) |
| 0.6.7 | 2026-10-24 | `e2280c9` | PR #19 | `TEST_RUNNER`: tests run on a foreign target; with no runner, `bmake test` stops (behaviour change) |
| 0.6.6 | 2026-10-24 | `1663aa9` | PR #18 | `file://` distfiles work without curl or wget |
| 0.6.5 | 2026-10-24 | `30b4f1a` | PR #17 | Asks the running make, not a command named bmake; unknown toolchains are explained |
| 0.6.4 | 2026-10-20 | `9e51d54` | PR #16 | Host, target and toolchain matrix that runs results on the target |
| 0.6.3 | 2026-10-15 | `089d2b6` | push | mingw-w64 runtime DLLs for `bmake run`; `ABI=` kept on re-execution |
| 0.6.2 | 2026-10-15 | `e4aef4b` | push | The pkg-config of the output being built; checked cache; emulated TLS |
| 0.6.1 | 2026-10-15 | `de07cb3` | push | `lib<name>.dll.a` import libraries; winpthread with clang |
| 0.6.0 | 2026-10-15 | `944b862` | push | `ABI=mingw`, real Windows ABI labels, loud and explained failures on Cygwin |

### 0.5: real-project hardening, constraints and run environment

| Version | Date | Commit | Landing | What changed |
|---|---|---|---|---|
| 0.5.9 | 2026-10-14 | `c7ad0ae` | PR #15 | `DOC_INPUT_EXTRA` and related documentation settings |
| 0.5.8 | 2026-10-03 | `193781e` | PR #13 | `bmake run` executes any program through the build environment |
| 0.5.7 | 2026-10-03 | `08da72a` | PR #12 | `test` builds first; OpenMP follows a static library |
| 0.5.6 | 2026-10-03 | `8ec9cdf` | PR #11 | `PLATFORMS=`, `TOOLCHAINS=` and `.tst` test modules |
| 0.5.5 | 2026-10-03 | `87048cd` | PR #10 | First Linux build of a real project; the suite passes on Linux |
| 0.5.4 | 2026-10-02 | `943b3b2` | PR #9 | A dependency `FETCH_BUILD` module does not reconfigure on its second build |
| 0.5.3 | 2026-10-02 | `c4d7295` | PR #8 | Dependents of a failure are skipped; each module is entered once |
| 0.5.2 | 2026-10-02 | `53619d9` | PR #7 | `REQUIRES=header:`; a second build is a no-op |
| 0.5.1 | 2026-10-01 | `173f44a` | PR #6 | Ten bugs found migrating lasviewer |
| 0.5.0 | 2026-09-28 | `21ab3c2` | PR #5 | Five bugs found migrating lasviewer, including no relink when a library changed |

### 0.4: C++ readiness and external software

| Version | Date | Commit | Landing | What changed |
|---|---|---|---|---|
| 0.4.3 | 2026-09-28 | `c1b19fe` | PR #4 | `REQUIRES=`: declare external prerequisite software |
| 0.4.2 | 2026-09-25 | `b29100e` | PR #3 | `FETCH_BUILD=`: fetched sources use their own build system |
| 0.4.1 | 2026-09-25 | `4a3698c` | PR #2 | `IMPORT=fetch:` and `fetch-bin:` |
| 0.4.0 | 2026-09-25 | `8982068` | PR #1 | C++ linking, real exit codes, header dependencies, rebuild on flag change, `IMPORT=`, `CXXSTD=`, `OPENMP=` |

### 0.3: tests, documentation, sanitizers and CI reports

| Version | Date | Commit | Landing | What changed |
|---|---|---|---|---|
| 0.3.6 | 2026-09-16 | `e3dcd16` | push | `scripts/install-env.sh` for projects outside this tree |
| 0.3.5 | 2026-09-16 | `405d62b` | push | Report dashboards no longer collide; `clean` removes them |
| 0.3.4 | 2026-09-16 | `8519a76` | push | `RUN_ID=`: run history is kept instead of overwritten |
| 0.3.3 | 2026-09-16 | `3442b49` | push | Build logs and dashboards; `REPORT=`, `FAIL_FAST=`, `TEST=`, `FW=` |
| 0.3.2 | 2026-09-16 | `9a430e5` | push | Workspace-wide test runs with one dashboard |
| 0.3.1 | 2026-09-16 | `c1ebf7f` | push | `SANITIZE=` |
| 0.3.0 | 2026-09-15 | `8570496` | push | Doxygen documentation, local-mk hooks, ATF/Kyua unit tests |

### 0.2.0 and landings with no number of their own

0.2.0 is the tagged starting point, from 2026-09-06.

| Stays on | Commit | Landing | What changed |
|---|---|---|---|
| 0.5.8 | `c3ddd44` | PR #14 | Specification of chapter 05: setup and administration |
| 0.3.5 | `fa7dd0c` | push | README: tier tables |
| 0.3.5 | `fb8e563` | push | README: what "tier 1" and "tier 2" mean |
| 0.3.5 | `5145944` | push | README: install and setup instructions |
| 0.3.5 | `0c8ffdc` | push | Model: build variants parked for later |
| 0.3.5 | `4d223a8` | push | Specification of Qt support |
| 0.3.0 | `c6b6523` | push | Documentation of the 0.3.0 features |
| 0.2.0 | `dd304fe` | push | Model: one missing link |
| 0.2.0 | `5a26a4c` | push | Model: recovered decisions, test matrix, unit tests, sanitizers |
| 0.2.0 | `b0f75aa` | push | Repository layout: `impl/` moved to the top level, `specs/` split up |
| 0.2.0 | `4857030` | push | README: the methodology behind the project |
