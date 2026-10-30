# contrib/

Third-party sources Bmake It builds from, kept as released.

## atf-0.23

ATF (Automated Testing Framework) 0.23, from the release tarball
`atf-0.23.tar.gz` (sha256
`a64e2427d021297f25b3f2e1798f8ec4dc3061ffb01a1cd3f66cc4cee486b10f`),
https://github.com/freebsd/atf. BSD 2-clause licence: `atf-0.23/COPYING`.

`atf-c` and `atf-c++` (sources, headers and their own tests), ATF's
`test-programs/` (the test-program interface checks) and the Kyuafiles,
plus the top-level headers, licence and notes. Not edited. Left out: atf-sh,
the documentation and the autotools build.

Built by `scripts/atf-build.sh` with `atf-bmk` below: always for native
Windows runtimes (`TOOLCHAIN=msvc`, `ABI=mingw`), which have no ATF to
install, and on any other target with `BMK_ATF=bundled` (otherwise the
installed ATF is used). See `docs/spec/80-unit-testing.md`, "The ATF Bmake
It carries", and `docs/spec/81-atf-feature-matrix.md`.

## atf-bmk

What Bmake It adds to build `atf-0.23` itself, and to test it (Bmake It's
licence):

- `include/atf-c/defs.h`: configure's output elsewhere, for every target;
  on POSIX the build script writes `config.h` from compile probes, as ATF's
  configure checks would.
- `win/`: the Windows compatibility layer, force-included in every source
  for a native Windows runtime -- `atfw-compat.h` / `atfw-compat.c` /
  `atfw-compat-cxx.cpp` (paths and `-s`/`-r` arguments, entry points,
  CRLF-tolerant comparison, `fork` stubs and the "not available" error);
  `regex.h` / `regex.cpp` (POSIX regcomp/regexec over `std::regex`);
  `err.h`, `sys/` (headers mingw-w64 and MSVC lack); `msvc/` and
  `atfw-msvc.c` (what only MSVC lacks: getopt, dirent, ...);
  `include-msvc/unistd.h` (staged for the test programs too); `user.c` (in
  place of ATF's: no uids on Windows); `config.h`. `win/test-shim/`: POSIX
  declarations for compiling ATF's *own* tests on Windows -- never a user's.
- `tests/`: atf-bmk's own tests -- each check macro and result, run one case
  at a time and checked against upstream's answers (no `fork`, so they cover
  Windows, where ATF's own `macros_test` cannot run).
- `expected/`: per mode (`posix`, `win`, and the `installed` baseline), each
  result of the self-test that is not a pass, with its reason.

### The self-test

`scripts/atf-selftest.sh OUTDIR` bootstraps atf-bmk: it builds the library,
builds ATF's own tests and atf-bmk's against it, runs them with Kyua and
compares with `expected/<mode>.txt`. Any other failure, and any listed line
that no longer happens, fails it. With `CC`, `CXX`, `AR`, `TOOLCHAIN` and
`ATF_BMK_MODE` (`posix`, `win`, or `installed` for the same tests against the
installed ATF -- the baseline that tells a host's behaviour from atf-bmk's):

```sh
CC=clang CXX=clang++ AR=ar TOOLCHAIN=llvm ATF_BMK_MODE=posix sh scripts/atf-selftest.sh /tmp/atf-st
```
