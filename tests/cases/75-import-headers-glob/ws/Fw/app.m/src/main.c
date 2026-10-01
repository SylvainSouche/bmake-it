#include <stdio.h>
#include "gdal_a.h"
#include "gdal_b.h"
int many_value(void);
int main(void) { printf("%d %d\n", GDAL_A, many_value()); return 0; }
