#include <atf-c.h>
#include "imp/api.h"
ATF_TC_WITHOUT_HEAD(value);
ATF_TC_BODY(value, tc) { ATF_REQUIRE_EQ(42, imp_value()); }
ATF_TP_ADD_TCS(tp) { ATF_TP_ADD_TC(tp, value); return atf_no_error(); }
