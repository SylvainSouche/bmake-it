#include "buf.h"
#include <stdlib.h>

int *make_buffer(size_t n) {
    return (int *)malloc(n * sizeof(int));
}

/*
 * Deliberate off-by-one heap-buffer-overflow (writes n+1 elements into
 * an n-element buffer) -- a sanitizer-catch fixture, not a shipped bug.
 * Kept in a separate compilation unit from its caller on purpose: at
 * -O2 (bmake's own sys.mk default), a single-TU version lets the
 * compiler prove the overflowing store is dead and silently drops it,
 * masking the very thing this test exists to prove.
 */
void fill_buffer(int *buf, size_t n) {
    for (size_t i = 0; i <= n; i++) {
        buf[i] = (int)i;
    }
}
