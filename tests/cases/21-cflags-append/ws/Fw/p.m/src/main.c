#include <stdio.h>
int main(void) {
#if TEST_FEATURE != 42
#error TEST_FEATURE not set
#endif
    return 0;
}
