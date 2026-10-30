// regex.cpp -- POSIX regcomp/regexec over std::regex (see regex.h).
#include "regex.h"

#include <cstring>
#include <new>
#include <regex>

extern "C" int
regcomp(regex_t *preg, const char *pattern, int cflags)
{
    std::regex::flag_type f = (cflags & REG_EXTENDED) ? std::regex::extended
                                                      : std::regex::basic;
    if (cflags & REG_ICASE)
        f |= std::regex::icase;
    if (cflags & REG_NOSUB)
        f |= std::regex::nosubs;
    try {
        std::regex *re = new std::regex(pattern, f);
        preg->atfw_impl = re;
        preg->re_nsub = re->mark_count();
        return 0;
    } catch (const std::regex_error&) {
        preg->atfw_impl = NULL;
        return REG_BADPAT;
    } catch (const std::bad_alloc&) {
        preg->atfw_impl = NULL;
        return REG_ESPACE;
    }
}

// A string ending in "\r" is matched without it: a line read from a file
// written in text mode on Windows ends in "\r\n", and "^sum=2$" must find
// "sum=2" there as it does on POSIX (atf_utils_grep_file reads lines up to
// the "\n").
extern "C" int
regexec(const regex_t *preg, const char *str, size_t nmatch,
        regmatch_t *pmatch, int)
{
    const std::regex *re = static_cast<const std::regex *>(preg->atfw_impl);
    std::cmatch m;
    size_t len = std::strlen(str);
    if (len > 0 && str[len - 1] == '\r')
        len--;
    if (!std::regex_search(str, str + len, m, *re))
        return REG_NOMATCH;
    for (size_t i = 0; i < nmatch; i++) {
        if (i < m.size() && m[i].matched) {
            pmatch[i].rm_so = static_cast<regoff_t>(m.position(i));
            pmatch[i].rm_eo = static_cast<regoff_t>(m.position(i) + m.length(i));
        } else {
            pmatch[i].rm_so = pmatch[i].rm_eo = -1;
        }
    }
    return 0;
}

extern "C" void
regfree(regex_t *preg)
{
    delete static_cast<std::regex *>(preg->atfw_impl);
    preg->atfw_impl = NULL;
}

extern "C" size_t
regerror(int errcode, const regex_t *, char *buf, size_t size)
{
    const char *msg = errcode == REG_NOMATCH ? "no match"
                    : errcode == REG_ESPACE ? "out of memory"
                    : "invalid regular expression";
    if (size > 0) {
        std::strncpy(buf, msg, size - 1);
        buf[size - 1] = '\0';
    }
    return std::strlen(msg) + 1;
}
