/* strings.h for MSVC (ATF building only). */
#if !defined(ATFW_STRINGS_H)
#define ATFW_STRINGS_H
#include <string.h>
#define strcasecmp _stricmp
#define strncasecmp _strnicmp
#endif
