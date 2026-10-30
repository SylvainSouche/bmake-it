/* sys/uio.h for a native Windows runtime: writev() as successive write()s
 * (tc.c writes the result file with it). */
#if !defined(ATFW_SYS_UIO_H)
#define ATFW_SYS_UIO_H
#include <stddef.h>
#include <io.h>

struct iovec {
    void *iov_base;
    size_t iov_len;
};

static __inline long
writev(int fd, const struct iovec *iov, int count)
{
    long total = 0;
    int i;
    for (i = 0; i < count; i++) {
        int n = _write(fd, iov[i].iov_base, (unsigned int)iov[i].iov_len);
        if (n < 0)
            return -1;
        total += n;
    }
    return total;
}
#endif
