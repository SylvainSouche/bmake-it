#include <atf-c++.hpp>
#include "cnt.h"
#ifndef EXPECTED
#define EXPECTED 1
#endif
ATF_TEST_CASE_WITHOUT_HEAD(value);
ATF_TEST_CASE_BODY(value) { ATF_REQUIRE_EQ(EXPECTED, cnt_value()); }
ATF_INIT_TEST_CASES(tcs) { ATF_ADD_TEST_CASE(tcs, value); }
