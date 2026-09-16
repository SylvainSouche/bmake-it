#include "calc.h"
#include <stdlib.h>

int *calc_make_buffer(size_t n)
{
    return (int *)malloc(n * sizeof(int));
}

/*
 * Deliberate off-by-one heap-buffer-overflow: writes n+1 elements into
 * an n-element buffer. Left in on purpose as a sanitizer-catch fixture
 * for SANITIZE=address -- see tests/calc_test.c and
 * docs/spec/80-unit-testing.md. Not a shipped-code bug to fix.
 */
void calc_fill_buffer(int *buf, size_t n)
{
    for (size_t i = 0; i <= n; i++) {
        buf[i] = (int)i;
    }
}

void calc_free_buffer(int *buf)
{
    free(buf);
}
