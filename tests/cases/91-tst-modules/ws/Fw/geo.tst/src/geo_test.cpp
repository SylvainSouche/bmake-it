#include <atf-c++.hpp>
#include "geo.h"
ATF_TEST_CASE_WITHOUT_HEAD(value);
ATF_TEST_CASE_BODY(value) { ATF_REQUIRE_EQ(5, geo_value()); }
ATF_INIT_TEST_CASES(tcs) { ATF_ADD_TEST_CASE(tcs, value); }
