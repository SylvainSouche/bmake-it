#include <atf-c.h>
#include "calc.h"

/*
 * Sanitizer-catch fixture: calc_fill_buffer has a deliberate off-by-one
 * heap-buffer-overflow (see src/calc.c). Under SANITIZE=address this
 * test aborts with an ASan report instead of passing -- that's the
 * point, proving the sanitizer actually catches a real bug rather than
 * just compiling flags through unused.
 */
ATF_TC_WITHOUT_HEAD(calc_overflow);
ATF_TC_BODY(calc_overflow, tc)
{
    int *buf = calc_make_buffer(4);
    calc_fill_buffer(buf, 4);
    calc_free_buffer(buf);
    ATF_REQUIRE(1);
}

ATF_TP_ADD_TCS(tp)
{
    ATF_TP_ADD_TC(tp, calc_overflow);
    return atf_no_error();
}
