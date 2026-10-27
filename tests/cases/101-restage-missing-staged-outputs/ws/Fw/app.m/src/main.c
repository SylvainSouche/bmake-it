#include <stdio.h>
#include "glm/glm.hpp"
#include "greet.h"

int main(void) {
    printf("%d %s\n", glm_version(), fakelib_greet());
    return 0;
}
