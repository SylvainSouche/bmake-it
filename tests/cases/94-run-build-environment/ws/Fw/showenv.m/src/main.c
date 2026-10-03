#include <stdio.h>
#include <stdlib.h>
/* prints NAME=value for each argument; "LIBVAR" prints the library search
   variable named by BMK_LIBVAR (macOS strips DYLD_* from system tools, so
   read it from a program of our own). */
int main(int c, char **v) {
    for (int i = 1; i < c; i++) {
        const char *name = v[i];
        if (name[0] == 'L' && name[1] == 'I' && name[2] == 'B' && name[3] == 'V') {
            const char *lv = getenv("BMK_LIBVAR");
            printf("LIBVAR=%s\n", lv && getenv(lv) ? getenv(lv) : "");
        } else {
            const char *val = getenv(name);
            printf("%s=%s\n", name, val ? val : "");
        }
    }
    return 0;
}
