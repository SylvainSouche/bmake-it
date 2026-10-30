/* atfw-compat.c -- what a native Windows runtime lacks for ATF (see
 * atfw-compat.h). */
#include <stdarg.h>
#include <stdbool.h>
#include <direct.h>
#include <windows.h>

#include "atf-c/detail/fs.h"
#include "atf-c/error.h"
#include "atf-c/macros.h"
#include "atf-c/tc.h"
#include "atf-c/tp.h"
#include "atf-c/utils.h"

static void
atfw_slashes(char *s)
{
    for (; s != NULL && *s != '\0'; s++)
        if (*s == '\\')
            *s = '/';
}

#undef getcwd
char *
atfw_getcwd(char *buf, int size)
{
    char *cwd = _getcwd(buf, size);
    atfw_slashes(cwd);
    return cwd;
}

bool
atf_fs_path_is_absolute(const atf_fs_path_t *p)
{
    const char *s = atf_fs_path_cstring(p);
    return s[0] == '/' || (((s[0] >= 'A' && s[0] <= 'Z') ||
        (s[0] >= 'a' && s[0] <= 'z')) && s[1] == ':' && s[2] == '/');
}

/* On entering a test program (C or C++): argv[0] as ATF expects it,
 * '/'-separated -- it finds the source directory and the program's name
 * from it; and stdout/stderr in binary mode -- Kyua reads the test case
 * list line by line and a text-mode "\r\n" breaks its header check. */
void
atfw_enter(int argc, char **argv)
{
    int i;

    if (argc > 0)
        atfw_slashes(argv[0]);
    /* -s <srcdir> and -r <resfile> (also -s<dir>, -r<file>): a Cygwin path,
     * as Kyua or an atf-sh test passes it, made a Windows one -- the source
     * directory is checked with stat(), which does not go through
     * atfw_open. (Only before the test case name: getopt stops there.) */
    for (i = 1; i < argc && argv[i][0] == '-'; i++) {
        char flag = argv[i][1];
        char **slot = NULL;
        const char *path;
        size_t skip = 0;

        if (strcmp(argv[i], "--") == 0)
            break;
        if ((flag == 's' || flag == 'r') && argv[i][2] == '\0' && i + 1 < argc)
            slot = &argv[++i];
        else if (flag == 's' || flag == 'r') {
            slot = &argv[i];
            skip = 2;
        } else if (flag == 'v' && argv[i][2] == '\0') {
            i++;  /* -v var=value: a value, not a path */
            continue;
        }
        if (slot != NULL) {
            char buf[4096];
            path = atfw_native_path(*slot + skip, buf, sizeof(buf));
            if (path != NULL && path != *slot + skip) {
                char *s = malloc(skip + strlen(path) + 1);
                if (s != NULL) {
                    memcpy(s, *slot, skip);
                    strcpy(s + skip, path);
                    *slot = s;
                }
            }
        }
    }
    _setmode(_fileno(stdout), _O_BINARY);
    _setmode(_fileno(stderr), _O_BINARY);
}

/* The entry point of a C test program; tp_main.c's own is renamed
 * (-DATFW_TP_MAIN_C). */
#undef atf_tp_main
int atfw_posix_tp_main(int, char **, atf_error_t (*)(atf_tp_t *));
int
atf_tp_main(int argc, char **argv, atf_error_t (*add_tcs_hook)(atf_tp_t *))
{
    atfw_enter(argc, argv);
    return atfw_posix_tp_main(argc, argv, add_tcs_hook);
}

int
atfw_setenv(const char *name, const char *value, int overwrite)
{
    if (!overwrite && getenv(name) != NULL)
        return 0;
    return _putenv_s(name, value) == 0 ? 0 : (errno = EINVAL, -1);
}

int
atfw_unsetenv(const char *name)
{
    return _putenv_s(name, "") == 0 ? 0 : (errno = EINVAL, -1);
}

/* The Cygwin root: ATFW_CYGROOT (`cygpath -m /`, as bmake test sets it),
 * else the parent of the PATH directory holding cygwin1.dll -- Kyua is a
 * Cygwin program, so its bin directory is on the PATH a native child gets
 * (a cmd: runner, a Kyua started by hand). NULL when neither is there. */
static const char *
atfw_cygroot(void)
{
    static char root[MAX_PATH];
    const char *env = getenv("ATFW_CYGROOT");
    const char *p;

    if (env != NULL && env[0] != '\0')
        return env;
    if (root[0] != '\0')
        return root;
    for (p = getenv("PATH"); p != NULL && *p != '\0'; ) {
        const char *end = strchr(p, ';');
        size_t len = end != NULL ? (size_t)(end - p) : strlen(p);
        char dll[MAX_PATH];
        if (len > 0 && len + 13 < sizeof(dll)) {
            memcpy(dll, p, len);
            strcpy(dll + len, "\\cygwin1.dll");
            if (GetFileAttributesA(dll) != INVALID_FILE_ATTRIBUTES) {
                char *s;
                memcpy(root, p, len);
                root[len] = '\0';
                atfw_slashes(root);
                while ((s = strrchr(root, '/')) != NULL && s[1] == '\0')
                    *s = '\0';
                if ((s = strrchr(root, '/')) != NULL)
                    *s = '\0';  /* <root>/bin -> <root> */
                return root;
            }
        }
        p = end != NULL ? end + 1 : NULL;
    }
    return NULL;
}

/* A Cygwin path as a Windows one: /cygdrive/<d>/rest -> <d>:/rest, and any
 * other absolute path (/tmp/...) under the Cygwin root. Any other path is
 * returned as is. NULL: an absolute Cygwin path and no Cygwin root known
 * -- the caller says so. */
const char *
atfw_native_path(const char *path, char *buf, size_t size)
{
    const char *root;

    if (strncmp(path, "/cygdrive/", 10) == 0 && path[10] != '\0' &&
        (path[11] == '/' || path[11] == '\0')) {
        snprintf(buf, size, "%c:%s", path[10], path[11] ? path + 11 : "/");
        return buf;
    }
    if (path[0] == '/' && path[1] != '/') {
        root = atfw_cygroot();
        if (root == NULL)
            return NULL;
        snprintf(buf, size, "%s%s", root, path);
        return buf;
    }
    return path;
}

#undef open
int
atfw_open(const char *path, int flags, ...)
{
    char buf[4096];
    int mode = 0;
    const char *native;

    if (flags & _O_CREAT) {
        va_list ap;
        va_start(ap, flags);
        mode = va_arg(ap, int);
        va_end(ap);
    }
    native = atfw_native_path(path, buf, sizeof(buf));
    if (native == NULL) {
        fprintf(stderr, "atf: %s: a Cygwin path that this native Windows "
            "program cannot open -- the Cygwin root is unknown: ATFW_CYGROOT "
            "(`cygpath -m /`) is not set and no cygwin1.dll is on PATH\n", path);
        errno = ENOENT;
        return -1;
    }
    return _open(native, flags, mode & (_S_IREAD | _S_IWRITE));
}

char *
atfw_mkdtemp(char *tmpl)
{
    size_t len = strlen(tmpl);
    int tries;

    if (len < 6 || strcmp(tmpl + len - 6, "XXXXXX") != 0) {
        errno = EINVAL;
        return NULL;
    }
    for (tries = 0; tries < 100; tries++) {
        unsigned v = (unsigned)GetTickCount() ^ ((unsigned)_getpid() << 16) ^
            (unsigned)(tries * 7919);
        int i;
        for (i = 0; i < 6; i++) {
            tmpl[len - 6 + i] = "abcdefghijklmnopqrstuvwxyz0123456789"[v % 36];
            v = v / 36 + (unsigned)rand();
        }
        if (_mkdir(tmpl) == 0)
            return tmpl;
        if (errno != EEXIST)
            return NULL;
    }
    return NULL;
}

int
atfw_fchmod(int fd, int mode)
{
    (void)fd; (void)mode;
    return 0;
}

int
pipe(int *fds)
{
    return _pipe(fds, 65536, _O_BINARY);
}

int
kill(int pid, int sig)
{
    (void)pid; (void)sig;
    errno = ENOSYS;
    return -1;
}

/* process.c's errors (it calls atf_libc_error, renamed to this when it is
 * built): "Failed to fork" says what is not available; any other passes. */
atf_error_t
atfw_process_libc_error(int syserrno, const char *fmt, ...)
{
    char buf[1024];
    va_list ap;

    if (syserrno == ENOSYS && strncmp(fmt, "Failed to fork", 14) == 0)
        return atf_libc_error(ENOSYS, "Running a program (atf_check_exec_array, "
            "atf_check_build_*, atf::check, atf::process) is not available in "
            "Bmake It's ATF for native Windows runtimes yet: it needs fork(2)");
    va_start(ap, fmt);
    vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);
    return atf_libc_error(syserrno, "%s", buf);
}

/* atf_utils_compare_file: true when the file holds exactly `contents`, or
 * holds it with "\r\n" for each "\n" -- what a test program writes in text
 * mode on Windows (std::ofstream, fopen "w"), which is the same text. */
bool
atf_utils_compare_file(const char *name, const char *contents)
{
    char buf[4096];
    const char *c = contents;
    int fd, n, i;
    bool pending_cr = false;

    fd = atfw_open(name, O_RDONLY | O_CLOEXEC);
    ATF_REQUIRE_MSG(fd != -1, "Cannot open %s", name);
    while ((n = _read(fd, buf, sizeof(buf))) > 0) {
        for (i = 0; i < n; i++) {
            if (pending_cr) {
                pending_cr = false;
                if (buf[i] == '\n' && *c == '\n') {
                    c++;
                    continue;
                }
                if (*c != '\r')
                    goto differ;
                c++;
            }
            if (buf[i] == '\r' && *c != '\r') {
                pending_cr = true;
                continue;
            }
            if (*c == '\0' || buf[i] != *c)
                goto differ;
            c++;
        }
    }
    _close(fd);
    return n == 0 && !pending_cr && *c == '\0';
differ:
    _close(fd);
    return false;
}

/* atf_utils_fork and atf_utils_wait start and reap a child process with
 * fork(2): not available for a native Windows runtime yet. A test case
 * that uses them fails saying so, instead of an obscure "fork failed". */
#undef atf_utils_fork
#undef atf_utils_wait
pid_t
atf_utils_fork(void)
{
    atf_tc_fail("atf_utils_fork is not available in Bmake It's ATF for "
        "native Windows runtimes (it needs fork(2)); keep this test case for "
        "POSIX targets");
}

void
atf_utils_wait(const pid_t pid, const int exitstatus, const char *expout,
    const char *experr)
{
    (void)pid; (void)exitstatus; (void)expout; (void)experr;
    atf_tc_fail("atf_utils_wait is not available in Bmake It's ATF for "
        "native Windows runtimes (it needs fork(2)); keep this test case for "
        "POSIX targets");
}
