# macros_test.sh -- atf-bmk's own tests (atf-sh; scripts/atf-selftest.sh
# prepends the interpreter): runs each case of c_macros_helpers and
# cpp_macros_helpers alone, with -r, and checks its exit status, its result
# file and, for a failing check, its message -- the answers upstream ATF
# 0.23 gives (recorded 2026-10-30 against the installed ATF). No fork in the
# helper: this covers ATF's check macros on a native Windows runtime, where
# ATF's own macros_test cannot run.

# run <helper> <case> <exit status> <result regex> [<stderr regex>] [args...]
run() {
    _h=$1; _c=$2; _rc=$3; _res=$4; _err=${5:-}
    shift 5 2>/dev/null || shift $#
    rm -f result
    atf_check -s exit:"$_rc" -o ignore -e save:stderr \
        "$(atf_get_srcdir)/$_h" -r result "$@" "$_c"
    atf_check -o match:"^$_res\$" cat result
    if [ -n "$_err" ]; then
        atf_check -o match:"$_err" cat stderr
    fi
}

# a failure's "<file>:<line>: " prefix
AT='.*_macros_helpers\.c(pp)?:[0-9]+: '

atf_test_case c_checks
c_checks_head() { atf_set "descr" "ATF_CHECK*: a pass, and a failure that does not stop the test case"; }
c_checks_body() {
    for c in check check_msg check_eq check_eq_msg check_inteq check_streq check_match check_errno; do
        run c_macros_helpers ${c}_pass 0 'passed'
    done
    F='failed: 1 checks failed; see output for more details'
    run c_macros_helpers check_fail 1 "$F" "one == 2 not met"
    run c_macros_helpers check_msg_fail 1 "$F" "one is 1"
    run c_macros_helpers check_eq_fail 1 "$F" "one != two"
    run c_macros_helpers check_eq_msg_fail 1 "$F" "values 1 and 2"
    run c_macros_helpers check_inteq_fail 1 "$F" 'one != two \(1 != 2\)'
    run c_macros_helpers check_streq_fail 1 "$F" '"abc" != "abd" \(abc != abd\)'
    run c_macros_helpers check_match_fail 1 "$F" "'\^x' not matched in 'abc'"
    run c_macros_helpers check_errno_fail 1 "$F" "Expected errno 2, got 13"
}

atf_test_case c_requires
c_requires_head() { atf_set "descr" "ATF_REQUIRE*: a pass, and a failure that ends the test case with its message"; }
c_requires_body() {
    for c in require require_msg require_eq require_inteq require_streq require_match require_errno; do
        run c_macros_helpers ${c}_pass 0 'passed'
    done
    run c_macros_helpers require_fail 1 "failed: ${AT}one == 2 not met"
    run c_macros_helpers require_msg_fail 1 "failed: ${AT}one is 1"
    run c_macros_helpers require_eq_fail 1 "failed: ${AT}one != two"
    run c_macros_helpers require_inteq_fail 1 "failed: ${AT}one != two \(1 != 2\)"
    run c_macros_helpers require_streq_fail 1 "failed: ${AT}\"abc\" != \"abd\" \(abc != abd\)"
    run c_macros_helpers require_match_fail 1 "failed: ${AT}'\[0-9\]\{3\}' not matched in 'a12b'"
    run c_macros_helpers require_errno_fail 1 "failed: ${AT}Expected errno 2, got 13, in -1 == -1"
}

atf_test_case c_results
c_results_head() { atf_set "descr" "atf_tc_pass/fail/fail_nonfatal/skip and atf_tc_require_prog"; }
c_results_body() {
    run c_macros_helpers result_pass 0 'passed'
    run c_macros_helpers result_fail 1 'failed: on purpose 7'
    run c_macros_helpers result_fail_nonfatal 1 'failed: 2 checks failed; see output for more details' 'second'
    run c_macros_helpers result_skip 0 'skipped: not today'
    run c_macros_helpers require_prog_missing 1 'failed: The required program no-such-prog-7f3e could not be found in the PATH'
}

atf_test_case c_expectations
c_expectations_head() { atf_set "descr" "atf_tc_expect_fail/pass/exit"; }
c_expectations_body() {
    run c_macros_helpers expect_fail_and_fail 0 "expected_failure: known: ${AT}one == 2 not met"
    run c_macros_helpers expect_fail_but_pass 1 'failed: Test case was expecting a failure but none were raised'
    run c_macros_helpers expect_pass_after_fail 0 'expected_failure: known: 1 checks failed as expected; see output for more details'
    run c_macros_helpers expect_exit_and_exit 3 'expected_exit\(3\): exits with 3'
}

atf_test_case c_metadata
c_metadata_head() { atf_set "descr" "metadata (descr, X-*) and configuration variables (-v)"; }
c_metadata_body() {
    run c_macros_helpers md_and_config 0 'passed' '' -v answer=42 -v flag=yes
    atf_check -o match:'^descr: reads its metadata and configuration$' -o match:'^X-custom: custom value$' \
        "$(atf_get_srcdir)/c_macros_helpers" -l
    # without the variable the case fails
    atf_check -s exit:1 -o ignore -e ignore "$(atf_get_srcdir)/c_macros_helpers" -r result md_and_config
}

atf_test_case c_cleanup
c_cleanup_head() { atf_set "descr" "a cleanup routine, run as <case>:cleanup"; }
c_cleanup_body() {
    atf_check -o match:'^has.cleanup: true$' "$(atf_get_srcdir)/c_macros_helpers" -l
    run c_macros_helpers with_cleanup 0 'passed'
    atf_check -o inline:'made\n' cat cookie
    atf_check -s exit:0 -o ignore -e ignore "$(atf_get_srcdir)/c_macros_helpers" -r result with_cleanup:cleanup
    atf_check -o inline:'yes\n' cat cleaned
}

atf_init_test_cases() {
    atf_add_test_case c_checks
    atf_add_test_case c_requires
    atf_add_test_case c_results
    atf_add_test_case c_expectations
    atf_add_test_case c_metadata
    atf_add_test_case c_cleanup
}
