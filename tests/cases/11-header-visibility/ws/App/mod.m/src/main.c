#include "mod_priv.h"
#include "app_loc.h"
#include "app_pub.h"
#include "sys_pub.h"
int main(void) {
    return SYS_PUBLIC + APP_PUBLIC + APP_LOCAL + MOD_PRIV - 4;
}
