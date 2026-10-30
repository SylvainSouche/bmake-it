/* The same source for every target: what Bmake It's ATF for native
 * Windows runtimes covers, plus one ATF feature it does not (a child
 * process with atf_utils_fork), which must fail there saying so. */
#include <atf-c.h>
#include <stdio.h>
#include <stdlib.h>

#include "calc.h"

ATF_TC_WITHOUT_HEAD(adds);
ATF_TC_BODY(adds, tc)
{
    ATF_CHECK_EQ(7, calc_add(3, 4));
    ATF_REQUIRE_MSG(calc_add(-1, 1) == 0, "calc_add(-1, 1) is %d", calc_add(-1, 1));
}

ATF_TC_WITHOUT_HEAD(files);
ATF_TC_BODY(files, tc)
{
    atf_utils_create_file("out.txt", "sum=%d\n", calc_add(20, 22));
    ATF_REQUIRE(atf_utils_file_exists("out.txt"));
    ATF_REQUIRE(atf_utils_compare_file("out.txt", "sum=42\n"));
    ATF_REQUIRE(atf_utils_grep_file("^sum=[0-9]+$", "out.txt"));
    ATF_REQUIRE(!atf_utils_grep_string("x{2}", "axb"));
}

ATF_TC(skipped);
ATF_TC_HEAD(skipped, tc)
{
    atf_tc_set_md_var(tc, "descr", "always skipped");
}
ATF_TC_BODY(skipped, tc)
{
    atf_tc_skip("on purpose");
}

ATF_TC_WITHOUT_HEAD(known_bug);
ATF_TC_BODY(known_bug, tc)
{
    atf_tc_expect_fail("calc_add is not multiplication");
    ATF_REQUIRE_EQ(6, calc_add(2, 3));
}

ATF_TC_WITHOUT_HEAD(child);
ATF_TC_BODY(child, tc)
{
    pid_t pid = atf_utils_fork();
    if (pid == 0) {
        printf("from the child\n");
        exit(EXIT_SUCCESS);
    }
    atf_utils_wait(pid, EXIT_SUCCESS, "from the child\n", "");
}

ATF_TP_ADD_TCS(tp)
{
    ATF_TP_ADD_TC(tp, adds);
    ATF_TP_ADD_TC(tp, files);
    ATF_TP_ADD_TC(tp, skipped);
    ATF_TP_ADD_TC(tp, known_bug);
    ATF_TP_ADD_TC(tp, child);
    return atf_no_error();
}
