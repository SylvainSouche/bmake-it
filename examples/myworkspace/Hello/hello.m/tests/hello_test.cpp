#include <atf-c++.hpp>
#include <climits>
#include "risky.h"

/*
 * Sanitizer-catch fixture: risky_add(INT_MAX, 1) is a signed-integer
 * overflow, undefined behavior in C. Under SANITIZE=undefined this test
 * aborts with a UBSan report instead of passing -- that's the point.
 */
ATF_TEST_CASE_WITHOUT_HEAD(hello_overflow);
ATF_TEST_CASE_BODY(hello_overflow)
{
    (void)risky_add(INT_MAX, 1);
    ATF_REQUIRE(true);
}

ATF_INIT_TEST_CASES(tcs)
{
    ATF_ADD_TEST_CASE(tcs, hello_overflow);
}
