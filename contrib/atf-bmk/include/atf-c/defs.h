/* atf-c/defs.h for Bmake It's ATF for native Windows runtimes (mingw-w64,
 * MSVC) -- configure generates it from defs.h.in on other systems. */
#if !defined(ATF_C_DEFS_H)
#define ATF_C_DEFS_H

#if defined(__GNUC__)
#define ATF_DEFS_ATTRIBUTE_FORMAT_PRINTF(a, b) __attribute__((__format__(__printf__, a, b)))
#define ATF_DEFS_ATTRIBUTE_NONNULL __attribute__((__nonnull__))
#define ATF_DEFS_ATTRIBUTE_NORETURN __attribute__((__noreturn__))
#define ATF_DEFS_ATTRIBUTE_UNUSED __attribute__((__unused__))
#else
/* (MSVC: ATF puts these after the declarator, where __declspec cannot go) */
#define ATF_DEFS_ATTRIBUTE_FORMAT_PRINTF(a, b)
#define ATF_DEFS_ATTRIBUTE_NONNULL
#define ATF_DEFS_ATTRIBUTE_NORETURN
#define ATF_DEFS_ATTRIBUTE_UNUSED
#endif

#endif /* !defined(ATF_C_DEFS_H) */
