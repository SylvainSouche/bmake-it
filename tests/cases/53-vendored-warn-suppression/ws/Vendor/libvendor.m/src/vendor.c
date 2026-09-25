#include "vendor.h"
/* deliberately triggers -Wunused-variable -- must NOT warn under
 * WARN=none */
int vendor_unused_fn(void) { int unused_var; return vendor_helper(0); }
