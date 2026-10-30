#include <atf-c++.hpp>
#include <cstdlib>
ATF_TEST_CASE_WITHOUT_HEAD(utility_is_reachable);
// (no shell syntax: a native Windows test program's system() is cmd.exe's)
ATF_TEST_CASE_BODY(utility_is_reachable) { ATF_REQUIRE_EQ(0, std::system("tool")); }
ATF_INIT_TEST_CASES(tcs) { ATF_ADD_TEST_CASE(tcs, utility_is_reachable); }
