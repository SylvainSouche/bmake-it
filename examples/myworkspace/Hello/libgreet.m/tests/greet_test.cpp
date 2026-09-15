#include <atf-c++.hpp>
#include "greet.h"

ATF_TEST_CASE_WITHOUT_HEAD(greet_smoke);
ATF_TEST_CASE_BODY(greet_smoke)
{
    greet("world");
    ATF_REQUIRE(true);
}

ATF_INIT_TEST_CASES(tcs)
{
    ATF_ADD_TEST_CASE(tcs, greet_smoke);
}
