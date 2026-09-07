#ifndef GREET_H
#define GREET_H

#include <bmk_export.h>
#if defined(GREET_BUILDING)
#  define GREET_EXPORT BMK_DLLEXPORT
#else
#  define GREET_EXPORT BMK_DLLIMPORT
#endif

GREET_EXPORT void greet(const char *name);
#endif
