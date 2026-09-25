#include "vendor.h"
#include <stdio.h>
int main(void) {
    /* App's OWN warning -- must still fire even though Vendor's is
     * suppressed both at its own source and via -isystem here. */
    int app_unused_var;
    printf("%d\n", vendor_helper(1));
    return 0;
}
