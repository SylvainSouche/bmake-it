#include <atf-c++.hpp>

extern "C" int calc_add(int, int);

ATF_TEST_CASE_WITHOUT_HEAD(sums);
ATF_TEST_CASE_BODY(sums)
{
    int s = 0;
    for (int i = 1; i <= 10; i++)
        s = calc_add(s, i);
    ATF_REQUIRE_EQ(55, s);
}

ATF_INIT_TEST_CASES(tcs)
{
    ATF_ADD_TEST_CASE(tcs, sums);
}
