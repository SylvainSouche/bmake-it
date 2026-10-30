/* libgen.h for MSVC (ATF building only): POSIX basename/dirname, in
 * atfw-msvc.c. */
#if !defined(ATFW_LIBGEN_H)
#define ATFW_LIBGEN_H

#if defined(__cplusplus)
extern "C" {
#endif

char *basename(char *);
char *dirname(char *);

#if defined(__cplusplus)
}
#endif
#endif
