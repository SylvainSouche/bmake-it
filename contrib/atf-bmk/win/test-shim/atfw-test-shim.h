/* atfw-test-shim.h -- force-included when scripts/atf-selftest.sh builds
 * ATF 0.23's OWN tests for a native Windows runtime (never a user's test
 * program): the POSIX declarations those tests and their helpers expect,
 * so they build and their differences show as results (listed, with the
 * reason, in contrib/atf-bmk/expected/win.txt) instead of build failures.
 * kill() is Bmake It's ATF's (it fails: ENOSYS), so a test that signals
 * itself does not get the signal. */
#if !defined(ATFW_TEST_SHIM_H)
#define ATFW_TEST_SHIM_H
#include <direct.h>
#include <io.h>
#include <process.h>
#include <signal.h>
#include <sys/types.h>
#include <unistd.h>

#if defined(__cplusplus)
extern "C" {
#endif
int kill(int, int);
int pipe(int *);
#if defined(__cplusplus)
}
#endif

typedef int uid_t;
typedef int gid_t;
#if defined(_MSC_VER)
typedef int mode_t;
#endif

#if !defined(SIGHUP)
#define SIGHUP 1
#endif
#if !defined(SIGQUIT)
#define SIGQUIT 3
#endif
#if !defined(SIGKILL)
#define SIGKILL 9
#endif
#if !defined(SIGUSR1)
#define SIGUSR1 30
#endif

/* POSIX mkdir(path, mode); the C runtime's takes the path only */
#define mkdir(p, m) _mkdir(p)
#endif
