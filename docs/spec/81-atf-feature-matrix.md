# Bmake It — 81: ATF Feature Matrix

Status: DRAFT, 2026-10-30. Every feature of ATF 0.23 (the version in
`contrib/atf-0.23`), against what the ATF Bmake It carries provides
(`80-unit-testing.md`, "The ATF Bmake It carries"), and what verifies it.

Columns:

- **ATF** — the installed ATF (BSD base systems, packages).
- **bmk POSIX** — `BMK_ATF=bundled` on a POSIX target: ATF's own sources,
  configured by Bmake It (`scripts/atf-build.sh`).
- **bmk Windows** — mingw-w64 and MSVC output: the same sources with the
  Windows layer (`contrib/atf-bmk/win`), run by the Cygwin Kyua.
- **Verified by** — **ST** is atf-bmk's own self-test
  (`scripts/atf-selftest.sh`, `atf-bmk-self-test-req`): ATF 0.23's own tests
  as released and atf-bmk's (`contrib/atf-bmk/tests`), run against atf-bmk
  in each mode, every difference from a pass listed with its reason in
  `contrib/atf-bmk/expected/`. *(posix)* / *(win)*: the mode it covers. A
  number is a Bmake It case (`tests/cases`), which checks the integration
  (`bmake test`), not the library.

Marks: **✔** provided, behaves as upstream; **≈** provided, with the
difference written beside it; **✗** not provided (fails as said); **K** the
installed Kyua does it, not the library (same on every column).

## Where the self-test stands (2026-10-30, Windows 10 host)

| Mode | Results | Pass | Known differences | Regressions |
|---|---|---|---|---|
| posix (Cygwin, clang) | 334 | 332 | 2: the host's (an administrator is not denied a mode-000 directory; upstream ATF fails them too) | 0 |
| installed (baseline: the same tests against the installed ATF) | 334 | 330 | 4: the 2 above, and 2 from how that ATF was configured | 0 |
| win (mingw-w64, clang) | 194 | 133 | 61: starting a process (50), POSIX signals (4), permission bits (2), tests that call POSIX-only functions (5, not built) | 0 |
| win (MSVC) | — | — | not run: the EWDK image's drive failed during the run | — |

`posix` matches upstream on everything ATF tests about itself. On Windows,
ATF's tests of the check macros (`macros_test`) run each case in a child
process and so cannot run; atf-bmk's own `macros_test` covers them there.

## Test programs and the Kyua interface

| Feature | ATF | bmk POSIX | bmk Windows | Verified by |
|---|---|---|---|---|
| `-l`: list the test cases and their metadata | ✔ | ✔ | ≈ stdout in binary mode (no `\r`) | ST meta_data_test (posix, win); 104 |
| `-r <file>`: write the result file | ✔ | ✔ | ≈ a Cygwin path is translated (`/cygdrive/<d>/`, else under the Cygwin root) | ST result_test (posix, win); 104 |
| Source directory from `argv[0]` | ✔ | ✔ | ≈ `argv[0]` made `/`-separated; `C:/` is absolute | ST srcdir_test (posix, win) |
| `-s <srcdir>` | ✔ | ✔ | ≈ a Cygwin path is translated | ST srcdir_test:sflag (posix, win) |
| `-v <var>=<value>`: configuration variables | ✔ | ✔ | ✔ | ST config_test, macros_test:c_metadata (posix, win) |
| `<case>:cleanup`: run the cleanup part | ✔ | ✔ | ✔ | ST macros_test:c_cleanup (posix, win) |
| One process per test case, own work directory | K | K | K | 104 |
| `timeout` metadata enforced (program killed) | K | K | K | ST expect_test:expect_timeout (posix, win) |
| A crash reported as a signal | K | K | ≈ an access violation is reported as signal 11 | by hand (win) |
| Exit code of a program that exits outside ATF | K | K | K | ST macros_test:c_expectations (posix, win) |
| `require.arch`, `require.config`, `require.files`, `require.machine`, `require.memory`, `require.progs`, `require.user` | K | K | ≈ evaluated by the Cygwin Kyua: Cygwin's `PATH`, uid and `uname` | — |
| `descr`, `X-*` metadata | ✔ | ✔ | ✔ | ST meta_data_test, macros_test:c_metadata (posix, win) |

## Defining test cases

| Feature | ATF | bmk POSIX | bmk Windows | Verified by |
|---|---|---|---|---|
| C: `ATF_TC`, `_HEAD`, `_BODY`, `_WITHOUT_HEAD`, `ATF_TP_ADD_TCS`, `ATF_TP_ADD_TC` | ✔ | ✔ | ✔ | ST tc_test, tp_test (posix, win) |
| C: `ATF_TC_WITH_CLEANUP`, `ATF_TC_CLEANUP` | ✔ | ✔ | ✔ | ST macros_test:c_cleanup (posix, win) |
| C++: `ATF_TEST_CASE`, `_HEAD`, `_BODY`, `_WITHOUT_HEAD`, `ATF_INIT_TEST_CASES`, `ATF_ADD_TEST_CASE` | ✔ | ✔ | ✔ | ST tests_test (posix, win); 104 |
| C++: `ATF_TEST_CASE_WITH_CLEANUP`, `ATF_TEST_CASE_CLEANUP`, `ATF_TEST_CASE_USE` | ✔ | ✔ | ✔ | ST atf-c++ macros_test (posix) |
| Metadata: `atf_tc_set_md_var`/`get_md_var`/`has_md_var`/`get_md_vars` (C++ alike) | ✔ | ✔ | ✔ | ST tc_test, tests_test, macros_test:c_metadata (posix, win) |
| Configuration: `atf_tc_get_config_var[_wd|_as_bool|_as_long]`, `has_config_var` (C++ alike) | ✔ | ✔ | ✔ | ST tc_test, macros_test:c_metadata (posix, win) |
| `.tst` modules (`TEST_PROG=`) | ✔ | ✔ | ✔ | 91, 104 |

## Checks

| Feature | ATF | bmk POSIX | bmk Windows | Verified by |
|---|---|---|---|---|
| `ATF_CHECK`, `ATF_REQUIRE` (+ `_MSG`) | ✔ | ✔ | ✔ | ST macros_test:c_checks, c_requires (posix, win); ATF macros_test (posix) |
| `ATF_CHECK_EQ`, `ATF_REQUIRE_EQ` (+ `_MSG`) | ✔ | ✔ | ✔ | likewise |
| `ATF_CHECK_INTEQ`, `ATF_REQUIRE_INTEQ` | ✔ | ✔ | ✔ | likewise |
| `ATF_CHECK_STREQ`, `ATF_REQUIRE_STREQ` | ✔ | ✔ | ✔ | likewise |
| `ATF_CHECK_MATCH`, `ATF_REQUIRE_MATCH` | ✔ | ✔ | ≈ `std::regex` (POSIX extended grammar); a trailing `\r` is ignored | likewise |
| `ATF_CHECK_ERRNO`, `ATF_REQUIRE_ERRNO` | ✔ | ✔ | ≈ the C runtime's `errno` values | likewise |
| C++: `ATF_REQUIRE`, `_EQ`, `_IN`, `_NOT_IN`, `_MATCH`, `_THROW`, `_THROW_RE`, `_ERRNO`, `ATF_CHECK_ERRNO`, `ATF_FAIL`, `ATF_PASS`, `ATF_SKIP` | ✔ | ✔ | ✔ (`_MATCH`, `_THROW_RE`: `std::regex`) | ST atf-c++ macros_test (posix); win: — (ATF's runs each case in a child; a C++ counterpart of atf-bmk's macros_test is to be written) |

## Results and expectations

| Feature | ATF | bmk POSIX | bmk Windows | Verified by |
|---|---|---|---|---|
| Pass, fail, `fail_nonfatal`, skip | ✔ | ✔ | ✔ | ST result_test, macros_test:c_results (posix, win) |
| `expect_pass`, `expect_fail` | ✔ | ✔ | ✔ | ST expect_test, macros_test:c_expectations (posix, win) |
| `expect_exit` | ✔ | ✔ | ✔ | ST expect_test:expect_exit (posix, win) |
| `expect_timeout` | ✔ | ✔ | ✔ | ST expect_test:expect_timeout (posix, win) |
| `expect_death` | ✔ | ✔ | ≈ no POSIX signals: a test case cannot signal itself | ST expect_test:expect_death (posix; win: listed) |
| `expect_signal` | ✔ | ✔ | ≈ no POSIX signals; `abort()` is exit code 3 | ST expect_test:expect_signal (posix; win: listed) |
| An exception escaping a C++ test body | aborts (SIGABRT) | aborts | aborts (exit code 3) | ST result_test:result_exception (posix; win: listed) |
| `atf_tc_require_prog` | ✔ | ✔ | ≈ looked up on the native `PATH` | ST macros_test:c_results (posix, win) |
| `atf_tc_check_errno`, `atf_tc_require_errno` | ✔ | ✔ | ≈ C runtime `errno` | ST macros_test (posix, win) |

## Utilities (`atf-c/utils.h`, `atf::utils`)

| Feature | ATF | bmk POSIX | bmk Windows | Verified by |
|---|---|---|---|---|
| `create_file`, `file_exists`, `cat_file`, `copy_file`, `readline`, `redirect`, `free_charpp`, `reset_resultsfile` | ✔ | ✔ | ✔ (`readline`: a text-mode line keeps its `\r`) | ST utils_test (posix; win: not built, it forks) |
| `compare_file` | ✔ | ✔ | ≈ also equal when the file has `\r\n` for each `\n` (text mode) | ST utils_test (posix); 104 (win) |
| `grep_file`, `grep_string` | ✔ | ✔ | ≈ `std::regex`; a line's trailing `\r` is ignored | ST utils_test (posix); 104 (win) |
| `fork`, `wait` | ✔ | ✔ | ✗ fails the test case: "not available ... (it needs fork(2))" | ST utils_test (posix); 104 (win: the message) |

## Running programs and building (`atf-c/check.h`, `atf-c/build.h`, `atf::check`, `atf::build`, `atf::process`)

| Feature | ATF | bmk POSIX | bmk Windows | Verified by |
|---|---|---|---|---|
| `atf_check_exec_array`, `atf_check_result_*` (C++ `atf::check::exec`, `check_result`) | ✔ | ✔ | ✗ built; fails: "Running a program ... is not available in Bmake It's ATF for native Windows runtimes yet: it needs fork(2)" | ST check_test (posix; win: listed) |
| `atf_check_build_c_o`, `_cpp`, `_cxx_o`; `atf_build_*` (C++ alike) | ✔ | ✔ | ✗ likewise | ST build_test, check_test (posix; win: listed) |

## atf-sh

| Feature | ATF | bmk POSIX | bmk Windows | Verified by |
|---|---|---|---|---|
| `atf-sh` script tests | ✔ | the installed `atf-sh` (not part of the bundled ATF) | Cygwin's `atf-sh`; scripts can run the native programs under test | ST test-programs/* (posix, win); 91, 99 |

## Bmake It's own paths around it

| Feature | Verified by |
|---|---|
| Built once per framework build root, by the first module needing it; not rebuilt by `bmake test` | 104 |
| `BMK_ATF=bundled|installed`; a misspelt value is an error | 104 |
| The public headers staged in `<build root>/atf/include`, as an install | 104, ST |
| "ATF not found" names `BMK_ATF=bundled` as an alternative | — |
| A compile error building it: file, compiler messages, log | — |
| Rebuilt when the compilers, `contrib/atf-bmk` or the build script change | — |
| A build of it left locked for 10 minutes: an error naming the lock | — |
| A Cygwin path it cannot translate: an error naming `ATFW_CYGROOT` | — |
