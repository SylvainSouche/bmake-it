#include <omp.h>
int work_sum(int n) { int s = 0;
#pragma omp parallel for reduction(+:s)
 for (int i = 0; i < n; i++) s += i;
 return s; }
