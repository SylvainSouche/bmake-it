#include "greet.h"
#include <stdio.h>

int main(int argc, char **argv)
{
    greet("Bmake It");
    for (int i = 1; i < argc; i++) {
        printf("arg: %s\n", argv[i]);
    }
    return 0;
}
