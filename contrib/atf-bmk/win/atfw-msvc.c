/* atfw-msvc.c -- the POSIX calls ATF makes that MSVC's C runtime lacks
 * (mingw-w64's has them): getopt, opendir/readdir/closedir, basename/
 * dirname, mkstemp. Built for TOOLCHAIN=msvc only. */
#include <ctype.h>
#include <stdio.h>
#include <string.h>
#include <windows.h>

#include "dirent.h"
#include "libgen.h"

/* --- getopt (POSIX: options before operands; ':' first in optstring
 * returns ':' for a missing argument) --- */
char *optarg = NULL;
int optind = 1, opterr = 1, optopt = 0;

int
getopt(int argc, char *const argv[], const char *optstring)
{
    static int pos = 1;  /* within argv[optind] */
    const char *p;
    char c;

    if (*optstring == '+' || *optstring == '-')
        optstring++;
    if (optind >= argc || argv[optind] == NULL || argv[optind][0] != '-' ||
        argv[optind][1] == '\0') {
        pos = 1;
        return -1;
    }
    if (strcmp(argv[optind], "--") == 0) {
        optind++;
        pos = 1;
        return -1;
    }
    c = argv[optind][pos];
    p = strchr(optstring, c);
    if (p == NULL || c == ':') {
        optopt = c;
        if (opterr && *optstring != ':')
            fprintf(stderr, "%s: unknown option -- %c\n", argv[0], c);
        if (argv[optind][++pos] == '\0') {
            optind++;
            pos = 1;
        }
        return '?';
    }
    if (p[1] == ':') {
        if (argv[optind][pos + 1] != '\0') {
            optarg = &argv[optind][pos + 1];
        } else if (optind + 1 < argc) {
            optarg = argv[++optind];
        } else {
            optopt = c;
            optind++;
            pos = 1;
            if (*optstring == ':')
                return ':';
            if (opterr)
                fprintf(stderr, "%s: option requires an argument -- %c\n",
                    argv[0], c);
            return '?';
        }
        optind++;
        pos = 1;
    } else if (argv[optind][++pos] == '\0') {
        optind++;
        pos = 1;
    }
    return c;
}

/* --- opendir / readdir / closedir --- */
struct atfw_dir {
    HANDLE h;
    WIN32_FIND_DATAA fd;
    int first;
    struct dirent ent;
};

DIR *
opendir(const char *path)
{
    char pattern[MAX_PATH + 3];
    DIR *d;

    if (snprintf(pattern, sizeof(pattern), "%s/*", path) >= (int)sizeof(pattern)) {
        errno = ENAMETOOLONG;
        return NULL;
    }
    d = calloc(1, sizeof(*d));
    if (d == NULL)
        return NULL;
    d->h = FindFirstFileA(pattern, &d->fd);
    if (d->h == INVALID_HANDLE_VALUE) {
        free(d);
        errno = ENOENT;
        return NULL;
    }
    d->first = 1;
    return d;
}

struct dirent *
readdir(DIR *d)
{
    if (!d->first && !FindNextFileA(d->h, &d->fd))
        return NULL;
    d->first = 0;
    strncpy(d->ent.d_name, d->fd.cFileName, sizeof(d->ent.d_name) - 1);
    d->ent.d_name[sizeof(d->ent.d_name) - 1] = '\0';
    return &d->ent;
}

int
closedir(DIR *d)
{
    FindClose(d->h);
    free(d);
    return 0;
}

/* --- basename / dirname (POSIX: may modify their argument) --- */
static int
atfw_issep(char c)
{
    return c == '/' || c == '\\';
}

char *
basename(char *path)
{
    static char dot[] = ".";
    char *end, *start;

    if (path == NULL || *path == '\0')
        return dot;
    end = path + strlen(path) - 1;
    while (end > path && atfw_issep(*end))
        *end-- = '\0';
    start = end;
    while (start > path && !atfw_issep(start[-1]))
        start--;
    return start;
}

char *
dirname(char *path)
{
    static char dot[] = ".";
    char *end;

    if (path == NULL || *path == '\0')
        return dot;
    end = path + strlen(path) - 1;
    while (end > path && atfw_issep(*end))
        end--;
    while (end > path && !atfw_issep(*end))
        end--;
    if (end == path && !atfw_issep(*end))
        return dot;
    while (end > path && atfw_issep(end[-1]))
        end--;
    if (end == path)
        end++;
    *end = '\0';
    return path;
}

/* --- mkstemp --- */
int
mkstemp(char *tmpl)
{
    size_t len = strlen(tmpl);
    int tries;

    if (len < 6 || strcmp(tmpl + len - 6, "XXXXXX") != 0) {
        errno = EINVAL;
        return -1;
    }
    for (tries = 0; tries < 100; tries++) {
        unsigned v = (unsigned)GetTickCount() ^ ((unsigned)_getpid() << 16) ^
            (unsigned)(tries * 7919);
        int i, fd;
        for (i = 0; i < 6; i++) {
            tmpl[len - 6 + i] = "abcdefghijklmnopqrstuvwxyz0123456789"[v % 36];
            v = v / 36 + (unsigned)rand();
        }
        fd = _open(tmpl, _O_RDWR | _O_CREAT | _O_EXCL | _O_BINARY,
            _S_IREAD | _S_IWRITE);
        if (fd != -1 || errno != EEXIST)
            return fd;
    }
    return -1;
}
