#pragma once
/* deliberately triggers -Wunused-parameter for anyone who compiles it
 * as an ordinary (non-system) header */
static inline int vendor_helper(int unused_param) { return 42; }
