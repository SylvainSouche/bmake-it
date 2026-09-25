#include "grammar.h"
#include <stdio.h>
int main(void){
#ifdef TOKEN_B
    printf("has-token-b\n");
#else
    printf("no-token-b\n");
#endif
    return 0;
}
