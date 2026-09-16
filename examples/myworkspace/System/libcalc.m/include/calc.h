#ifndef CALC_H
#define CALC_H

#include <bmk_export.h>
#include <stddef.h>

#if defined(CALC_BUILDING)
#  define CALC_EXPORT BMK_DLLEXPORT
#else
#  define CALC_EXPORT BMK_DLLIMPORT
#endif

#ifdef __cplusplus
extern "C" {
#endif

CALC_EXPORT int *calc_make_buffer(size_t n);
CALC_EXPORT void calc_fill_buffer(int *buf, size_t n);
CALC_EXPORT void calc_free_buffer(int *buf);

#ifdef __cplusplus
}
#endif
#endif
