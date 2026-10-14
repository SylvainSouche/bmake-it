#include "../../local/include/a.h"
int a_undocumented_source(void) { return 0; }
int a_documented(void) { return a_undocumented_source(); }
int a_undocumented_local(void) { return 1; }
