/* user.c for a native Windows runtime, in place of atf-c/detail/user.c:
 * no uids. The test program never runs as root; Kyua checks require.user
 * itself before running a test case. */
#include "atf-c/detail/user.h"

uid_t
atf_user_euid(void)
{
    return 1000;
}

bool
atf_user_is_member_of_group(gid_t gid)
{
    (void)gid;
    return false;
}

bool
atf_user_is_root(void)
{
    return false;
}

bool
atf_user_is_unprivileged(void)
{
    return true;
}
