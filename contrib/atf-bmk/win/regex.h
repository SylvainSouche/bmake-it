/* regex.h for a native Windows runtime: the POSIX calls ATF makes
 * (regcomp with REG_EXTENDED, regexec for a match/no-match answer),
 * implemented over C++ std::regex's POSIX extended grammar in regex.cpp. */
#if !defined(ATFW_REGEX_H)
#define ATFW_REGEX_H
#include <stddef.h>

#if defined(__cplusplus)
extern "C" {
#endif

typedef struct {
    size_t re_nsub;
    void *atfw_impl;
} regex_t;
typedef long regoff_t;
typedef struct {
    regoff_t rm_so;
    regoff_t rm_eo;
} regmatch_t;

#define REG_EXTENDED 1
#define REG_ICASE    2
#define REG_NOSUB    4
#define REG_NEWLINE  8
#define REG_NOMATCH  1
#define REG_BADPAT   2
#define REG_ESPACE   12

int regcomp(regex_t *, const char *, int);
int regexec(const regex_t *, const char *, size_t, regmatch_t *, int);
void regfree(regex_t *);
size_t regerror(int, const regex_t *, char *, size_t);

#if defined(__cplusplus)
}
#endif
#endif
