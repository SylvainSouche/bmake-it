#include <atf-c.h>

ATF_TC_WITHOUT_HEAD(bad_test);
ATF_TC_BODY(bad_test, tc)
{
    /* Deliberately fails -- this is the point of the test case. */
    ATF_REQUIRE(0);
}

ATF_TP_ADD_TCS(tp)
{
    ATF_TP_ADD_TC(tp, bad_test);
    return atf_no_error();
}
