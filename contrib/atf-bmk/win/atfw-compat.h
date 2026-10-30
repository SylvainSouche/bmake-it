/* atfw-compat.h -- force-included (-include / /FI) in every ATF source built
 * for a native Windows runtime (mingw-w64, MSVC) by scripts/atf-build.sh.
 * ATF's sources (contrib/atf-0.23) stay as released; what Windows lacks is
 * supplied here, in the headers beside this one, and in atfw-compat.c. */
#if !defined(ATFW_COMPAT_H)
#define ATFW_COMPAT_H

#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <io.h>
#include <process.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>  /* (MSVC: contrib/atf-bmk/win/include-msvc) */

#if defined(__cplusplus)
extern "C" {
#endif

typedef int uid_t;
typedef int gid_t;
#if defined(_MSC_VER)
typedef int mode_t;
#include <basetsd.h>
typedef SSIZE_T ssize_t;
#define strcasecmp _stricmp
#define strncasecmp _strnicmp
#define strtok_r strtok_s
#define ftruncate _chsize
#endif

/* Result files and the files atf_utils_* write are read back byte for
 * byte (Kyua parses "passed\n"): binary, never text mode, and not inherited. */
#undef O_CLOEXEC
#define O_CLOEXEC (_O_NOINHERIT | _O_BINARY)

/* Kyua runs from Cygwin and hands the test program Cygwin paths
 * (-r/cygdrive/c/.../result.atf, or /tmp/... under the Cygwin root). Every
 * open() goes through atfw_open, which makes them Windows paths
 * (atfw_native_path; the root from ATFW_CYGROOT or cygwin1.dll's place on
 * PATH) and says plainly when it cannot. */
int atfw_open(const char *, int, ...);
const char *atfw_native_path(const char *, char *, size_t);
int atfw_setenv(const char *, const char *, int);
int atfw_unsetenv(const char *);
/* Paths in ATF are '/'-separated: the working directory too (getcwd gives
 * C:\..., made C:/...). atf_fs_path_is_absolute also knows C:/ -- fs.c's
 * own is renamed when building it (-DATFW_FS_C); atfw-compat.c has it.
 * The entry points (atf_tp_main for C, atf::tests::run_tp for C++) are
 * renamed the same way: atfw-compat.c and atfw-compat-cxx.cpp wrap them to
 * set up the process for Kyua first (atfw_enter). */
char *atfw_getcwd(char *, int);
#if defined(ATFW_FS_C)
#define atf_fs_path_is_absolute atfw_posix_fs_path_is_absolute
#endif
#if defined(ATFW_TP_MAIN_C)
#define atf_tp_main atfw_posix_tp_main
#endif
#if defined(ATFW_TESTS_CPP)
#define run_tp atfw_posix_run_tp
#endif
/* atf_utils_compare_file also takes a file written in text mode ("\r\n"
 * line ends) as equal to the "\n"-ended contents (atfw-compat.c). */
#if defined(ATFW_UTILS_C)
#define atf_utils_compare_file atfw_posix_utils_compare_file
#endif
/* (C sources only: in C++ the names would also rename std::fstream::open
 * and atf::utils::fork; the C++ part calls none of them directly.) */
#if !defined(__cplusplus)
#define getcwd atfw_getcwd
#define open atfw_open
#define setenv atfw_setenv
#define unsetenv atfw_unsetenv
#endif

/* No symbolic links, sockets or whiteouts to tell apart. */
#define lstat stat
#if !defined(S_IFLNK)
#define S_IFLNK  0xA000
#endif
#if !defined(S_IFSOCK)
#define S_IFSOCK 0xC000
#endif
#if !defined(S_IFBLK)
#define S_IFBLK  0x3000
#endif
#if !defined(S_IFIFO)
#define S_IFIFO  _S_IFIFO
#endif
#if !defined(S_IRUSR)
#define S_IRUSR _S_IREAD
#define S_IWUSR _S_IWRITE
#define S_IXUSR _S_IEXEC
#endif
#if !defined(S_IRWXU)
#define S_IRWXU (S_IRUSR | S_IWUSR | S_IXUSR)
#endif
#if !defined(S_IRGRP)
#define S_IRGRP 0
#define S_IWGRP 0
#define S_IXGRP 0
#define S_IRWXG 0
#define S_IROTH 0
#define S_IWOTH 0
#define S_IXOTH 0
#define S_IRWXO 0
#endif

char *atfw_mkdtemp(char *);
#define mkdtemp atfw_mkdtemp
int atfw_fchmod(int, int);
#define fchmod atfw_fchmod

/* atf_utils_fork / atf_utils_wait need fork(2): the Windows build replaces
 * them with versions that fail the test case saying so (atfw-compat.c). */
#define atf_utils_fork atfw_posix_utils_fork
#define atf_utils_wait atfw_posix_utils_wait
#if !defined(__cplusplus)
#define fork() (errno = ENOSYS, -1)
#endif
/* Running a program (atf_check_*, atf::check, atf::process) forks too: in
 * process.c (-DATFW_PROCESS_C) its "Failed to fork" error is replaced by
 * one naming what is not available (atfw_process_libc_error). pipe() and
 * kill() for process.c/process.cpp to build: kill() fails (ENOSYS). */
#if defined(ATFW_PROCESS_C)
#define atf_libc_error atfw_process_libc_error
#endif
int pipe(int *);
int kill(int, int);

#if defined(__cplusplus)
}
#endif

/* configure's defines: build.c reads ATF_BUILD_* without including it */
#include "config.h"

#endif
