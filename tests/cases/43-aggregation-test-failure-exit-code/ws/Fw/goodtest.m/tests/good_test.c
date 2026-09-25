#include <atf-c.h>

ATF_TC_WITHOUT_HEAD(good_test);
ATF_TC_BODY(good_test, tc)
{
    ATF_REQUIRE(1);
}

ATF_TP_ADD_TCS(tp)
{
    ATF_TP_ADD_TC(tp, good_test);
    return atf_no_error();
}
