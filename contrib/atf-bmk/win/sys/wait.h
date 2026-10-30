/* sys/wait.h for a native Windows runtime: the status macros, and a
 * waitpid() that fails -- nothing is ever forked (atfw-compat.h). */
#if !defined(ATFW_SYS_WAIT_H)
#define ATFW_SYS_WAIT_H
#include <errno.h>
#define WIFEXITED(s)   (((s) & 0x7f) == 0)
#define WEXITSTATUS(s) (((s) >> 8) & 0xff)
#define WIFSIGNALED(s) (((s) & 0x7f) != 0 && ((s) & 0x7f) != 0x7f)
#define WTERMSIG(s)    ((s) & 0x7f)
#define WCOREDUMP(s)   ((s) & 0x80)
#define waitpid(p, s, o) (errno = ECHILD, -1)
#endif
