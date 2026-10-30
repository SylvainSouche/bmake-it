/* unistd.h for MSVC, which has none: what ATF's public headers need of it
 * (atf-c/utils.h, atf-c++/utils.hpp: pid_t) and the descriptor calls. On
 * the include path of test programs built with TOOLCHAIN=msvc only. */
#if !defined(ATFW_UNISTD_H)
#define ATFW_UNISTD_H
#include <io.h>
#include <process.h>
#include <direct.h>

#if !defined(ATFW_PID_T)
#define ATFW_PID_T
typedef int pid_t;
#endif

#if !defined(STDIN_FILENO)
#define STDIN_FILENO  0
#define STDOUT_FILENO 1
#define STDERR_FILENO 2
#endif

#if !defined(F_OK)
#define F_OK 0
#define W_OK 2
#define R_OK 4
#define X_OK 0
#endif

/* (contrib/atf-bmk/win/atfw-msvc.c, in Bmake It's atf-c.lib) */
#if defined(__cplusplus)
extern "C" {
#endif
extern char *optarg;
extern int optind, opterr, optopt;
int getopt(int, char *const[], const char *);
int mkstemp(char *);
#if defined(__cplusplus)
}
#endif
#endif
