/* bmk_export.h -- portable shared-library export/import macro, in the
 * spirit of CAA/RADE's per-component ExportedBy<Framework> macros.
 *
 * A library's public header declares its own two-line boilerplate naming
 * ITS OWN export macro (so multiple libraries in the same translation
 * unit never collide on a single global macro name), then tags every
 * exported symbol with it:
 *
 *     #include <bmk_export.h>
 *     #if defined(GREET_BUILDING)
 *     #  define GREET_EXPORT BMK_DLLEXPORT
 *     #else
 *     #  define GREET_EXPORT BMK_DLLIMPORT
 *     #endif
 *
 *     GREET_EXPORT void greet(const char *name);
 *
 * mk.lib.mk automatically defines <LIB>_BUILDING (LIB=, uppercased) via
 * -D when compiling that module's OWN sources -- never for consumers,
 * who only ever see the plain header and therefore resolve to
 * BMK_DLLIMPORT. On non-Windows targets both expand to the platform's
 * usual "make this symbol visible" attribute (or nothing, pre-GCC4),
 * since ELF/Mach-O shared libraries export every global symbol by
 * default and have no import/export distinction to make.
 *
 * Optional for functions: an unannotated DLL exports every external
 * symbol its objects define on every Windows toolchain too (with MSVC
 * through a generated .def, msvc-shared-lib-export-req). A data symbol
 * used from another module still needs BMK_DLLIMPORT on the consumer's
 * side under MSVC, which has no auto-import.
 */
#ifndef BMK_EXPORT_H
#define BMK_EXPORT_H

#if defined(_WIN32) || defined(__CYGWIN__)
#  define BMK_DLLEXPORT __declspec(dllexport)
#  define BMK_DLLIMPORT __declspec(dllimport)
#else
#  if defined(__GNUC__) && __GNUC__ >= 4
#    define BMK_DLLEXPORT __attribute__((visibility("default")))
#  else
#    define BMK_DLLEXPORT
#  endif
#  define BMK_DLLIMPORT
#endif

#endif /* BMK_EXPORT_H */
