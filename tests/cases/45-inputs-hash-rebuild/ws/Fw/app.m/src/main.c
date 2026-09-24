#include "buf.h"
#include <stdio.h>
#include <stdlib.h>
int main(void) {
    int *buf = make_buffer(4);
    fill_buffer(buf, 4);
    printf("no crash\n");
    free(buf);
    return 0;
}
