/* sys/param.h for MSVC (ATF building only). */
#if !defined(ATFW_SYS_PARAM_H)
#define ATFW_SYS_PARAM_H
#include <stdlib.h>
#if !defined(MAXPATHLEN)
#define MAXPATHLEN _MAX_PATH
#endif
#endif
