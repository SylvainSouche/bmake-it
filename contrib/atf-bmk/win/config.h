/* config.h for Bmake It's ATF for native Windows runtimes -- configure
 * generates it on other systems; only what the built sources read. */
#if !defined(ATFW_CONFIG_H)
#define ATFW_CONFIG_H
#define PACKAGE "atf"
#define PACKAGE_NAME "Automated Testing Framework"
#define PACKAGE_VERSION "0.23"
#define PACKAGE_STRING "Automated Testing Framework 0.23"
#define PACKAGE_BUGREPORT "freebsd-testing@freebsd.org"
#define PACKAGE_COPYRIGHT "Copyright (c) 2007-2012 The NetBSD Foundation, Inc."
#define HAVE_GETCWD_DYN 1
/* atf_check_build_* defaults (also read from the environment); running a
 * compiler needs process support, not available on Windows yet */
#if !defined(ATF_BUILD_CC)
#define ATF_BUILD_CC "cc"
#define ATF_BUILD_CFLAGS ""
#define ATF_BUILD_CPP "cpp"
#define ATF_BUILD_CPPFLAGS ""
#define ATF_BUILD_CXX "c++"
#define ATF_BUILD_CXXFLAGS ""
#define ATF_INCLUDEDIR ""
#endif
#endif
