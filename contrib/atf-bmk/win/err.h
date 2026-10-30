/* err.h for a native Windows runtime (BSD err/errx/warn/warnx). */
#if !defined(ATFW_ERR_H)
#define ATFW_ERR_H
#include <errno.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static __inline void
atfw_vwarn_(int with_errno, const char *fmt, va_list ap)
{
    int e = errno;
    fprintf(stderr, "atf: ");
    if (fmt != NULL)
        vfprintf(stderr, fmt, ap);
    if (with_errno)
        fprintf(stderr, "%s%s", fmt != NULL ? ": " : "", strerror(e));
    fprintf(stderr, "\n");
}

static __inline void
warn(const char *fmt, ...)
{
    va_list ap; va_start(ap, fmt); atfw_vwarn_(1, fmt, ap); va_end(ap);
}

static __inline void
warnx(const char *fmt, ...)
{
    va_list ap; va_start(ap, fmt); atfw_vwarn_(0, fmt, ap); va_end(ap);
}

static __inline void
err(int status, const char *fmt, ...)
{
    va_list ap; va_start(ap, fmt); atfw_vwarn_(1, fmt, ap); va_end(ap);
    exit(status);
}

static __inline void
errx(int status, const char *fmt, ...)
{
    va_list ap; va_start(ap, fmt); atfw_vwarn_(0, fmt, ap); va_end(ap);
    exit(status);
}
#endif
