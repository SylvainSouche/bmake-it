/* c_macros_helpers.c -- atf-bmk's own tests: one test case per outcome of
 * every atf-c check macro and result call, run one at a time by
 * macros_test (an atf-sh script) with -r, which checks the result file.
 * ATF's own macros_test runs each case in a forked child instead, which a
 * native Windows runtime cannot do: this covers the macros there, and the
 * same file runs on POSIX against both ATFs. */
#include <atf-c.h>

#include <errno.h>
#include <stdlib.h>

#define PASS_FAIL(name, pass_body, fail_body) \
    ATF_TC_WITHOUT_HEAD(name ## _pass); \
    ATF_TC_BODY(name ## _pass, tc) { pass_body; } \
    ATF_TC_WITHOUT_HEAD(name ## _fail); \
    ATF_TC_BODY(name ## _fail, tc) { fail_body; }

static int one = 1, two = 2;

PASS_FAIL(check, ATF_CHECK(one == 1), ATF_CHECK(one == 2))
PASS_FAIL(check_msg, ATF_CHECK_MSG(one == 1, "one is %d", one),
          ATF_CHECK_MSG(one == 2, "one is %d", one))
PASS_FAIL(check_eq, ATF_CHECK_EQ(one, 1), ATF_CHECK_EQ(one, two))
PASS_FAIL(check_eq_msg, ATF_CHECK_EQ_MSG(one, 1, "x"),
          ATF_CHECK_EQ_MSG(one, two, "values %d and %d", one, two))
PASS_FAIL(check_inteq, ATF_CHECK_INTEQ(one, 1), ATF_CHECK_INTEQ(one, two))
PASS_FAIL(check_streq, ATF_CHECK_STREQ("abc", "abc"), ATF_CHECK_STREQ("abc", "abd"))
PASS_FAIL(check_match, ATF_CHECK_MATCH("b+c", "abbbcd"), ATF_CHECK_MATCH("^x", "abc"))
PASS_FAIL(check_errno, { errno = ENOENT; ATF_CHECK_ERRNO(ENOENT, -1 == -1); },
          { errno = EACCES; ATF_CHECK_ERRNO(ENOENT, -1 == -1); })
PASS_FAIL(require, ATF_REQUIRE(one == 1), ATF_REQUIRE(one == 2))
PASS_FAIL(require_msg, ATF_REQUIRE_MSG(one == 1, "x"),
          ATF_REQUIRE_MSG(one == 2, "one is %d", one))
PASS_FAIL(require_eq, ATF_REQUIRE_EQ(one, 1), ATF_REQUIRE_EQ(one, two))
PASS_FAIL(require_inteq, ATF_REQUIRE_INTEQ(one, 1), ATF_REQUIRE_INTEQ(one, two))
PASS_FAIL(require_streq, ATF_REQUIRE_STREQ("abc", "abc"), ATF_REQUIRE_STREQ("abc", "abd"))
PASS_FAIL(require_match, ATF_REQUIRE_MATCH("^a.c$", "abc"), ATF_REQUIRE_MATCH("[0-9]{3}", "a12b"))
PASS_FAIL(require_errno, { errno = ENOENT; ATF_REQUIRE_ERRNO(ENOENT, -1 == -1); },
          { errno = EACCES; ATF_REQUIRE_ERRNO(ENOENT, -1 == -1); })

/* results */
ATF_TC_WITHOUT_HEAD(result_pass);
ATF_TC_BODY(result_pass, tc) { atf_tc_pass(); }
ATF_TC_WITHOUT_HEAD(result_fail);
ATF_TC_BODY(result_fail, tc) { atf_tc_fail("on purpose %d", 7); }
ATF_TC_WITHOUT_HEAD(result_fail_nonfatal);
ATF_TC_BODY(result_fail_nonfatal, tc)
{
    atf_tc_fail_nonfatal("first");
    atf_tc_fail_nonfatal("second");
}
ATF_TC_WITHOUT_HEAD(result_skip);
ATF_TC_BODY(result_skip, tc) { atf_tc_skip("not today"); }
ATF_TC_WITHOUT_HEAD(expect_fail_and_fail);
ATF_TC_BODY(expect_fail_and_fail, tc)
{
    atf_tc_expect_fail("known");
    ATF_REQUIRE(one == 2);
}
ATF_TC_WITHOUT_HEAD(expect_fail_but_pass);
ATF_TC_BODY(expect_fail_but_pass, tc) { atf_tc_expect_fail("known"); }
ATF_TC_WITHOUT_HEAD(expect_pass_after_fail);
ATF_TC_BODY(expect_pass_after_fail, tc)
{
    atf_tc_expect_fail("known");
    ATF_CHECK(one == 2);
    atf_tc_expect_pass();
    ATF_CHECK(one == 1);
}
ATF_TC_WITHOUT_HEAD(expect_exit_and_exit);
ATF_TC_BODY(expect_exit_and_exit, tc)
{
    atf_tc_expect_exit(3, "exits with 3");
    exit(3);
}
ATF_TC_WITHOUT_HEAD(require_prog_missing);
ATF_TC_BODY(require_prog_missing, tc) { atf_tc_require_prog("no-such-prog-7f3e"); }

/* metadata and configuration */
ATF_TC(md_and_config);
ATF_TC_HEAD(md_and_config, tc)
{
    atf_tc_set_md_var(tc, "descr", "reads its metadata and configuration");
    atf_tc_set_md_var(tc, "X-custom", "custom value");
}
ATF_TC_BODY(md_and_config, tc)
{
    ATF_REQUIRE_STREQ("custom value", atf_tc_get_md_var(tc, "X-custom"));
    ATF_REQUIRE(atf_tc_has_config_var(tc, "answer"));
    ATF_REQUIRE_STREQ("42", atf_tc_get_config_var(tc, "answer"));
    ATF_REQUIRE_EQ(42, atf_tc_get_config_var_as_long(tc, "answer"));
    ATF_REQUIRE(atf_tc_get_config_var_as_bool(tc, "flag"));
    ATF_REQUIRE_STREQ("fallback", atf_tc_get_config_var_wd(tc, "missing", "fallback"));
}

/* a cleanup routine runs as "<case>:cleanup" */
ATF_TC_WITH_CLEANUP(with_cleanup);
ATF_TC_HEAD(with_cleanup, tc) { atf_tc_set_md_var(tc, "descr", "has a cleanup"); }
ATF_TC_BODY(with_cleanup, tc) { atf_utils_create_file("cookie", "made\n"); }
ATF_TC_CLEANUP(with_cleanup, tc) { atf_utils_create_file("cleaned", "yes\n"); }

#define ADD(name) ATF_TP_ADD_TC(tp, name ## _pass); ATF_TP_ADD_TC(tp, name ## _fail)
ATF_TP_ADD_TCS(tp)
{
    ADD(check); ADD(check_msg); ADD(check_eq); ADD(check_eq_msg);
    ADD(check_inteq); ADD(check_streq); ADD(check_match); ADD(check_errno);
    ADD(require); ADD(require_msg); ADD(require_eq); ADD(require_inteq);
    ADD(require_streq); ADD(require_match); ADD(require_errno);
    ATF_TP_ADD_TC(tp, result_pass);
    ATF_TP_ADD_TC(tp, result_fail);
    ATF_TP_ADD_TC(tp, result_fail_nonfatal);
    ATF_TP_ADD_TC(tp, result_skip);
    ATF_TP_ADD_TC(tp, expect_fail_and_fail);
    ATF_TP_ADD_TC(tp, expect_fail_but_pass);
    ATF_TP_ADD_TC(tp, expect_pass_after_fail);
    ATF_TP_ADD_TC(tp, expect_exit_and_exit);
    ATF_TP_ADD_TC(tp, require_prog_missing);
    ATF_TP_ADD_TC(tp, md_and_config);
    ATF_TP_ADD_TC(tp, with_cleanup);
    return atf_no_error();
}
