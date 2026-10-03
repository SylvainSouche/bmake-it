#include <atf-c++.hpp>
#include <cstdlib>
ATF_TEST_CASE_WITHOUT_HEAD(utility_is_reachable);
ATF_TEST_CASE_BODY(utility_is_reachable) { ATF_REQUIRE_EQ(0, std::system("tool >/dev/null")); }
ATF_INIT_TEST_CASES(tcs) { ATF_ADD_TEST_CASE(tcs, utility_is_reachable); }
