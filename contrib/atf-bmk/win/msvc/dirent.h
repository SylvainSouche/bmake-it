/* dirent.h for MSVC (ATF building only): opendir/readdir/closedir over
 * FindFirstFile, in atfw-msvc.c. */
#if !defined(ATFW_DIRENT_H)
#define ATFW_DIRENT_H

#if defined(__cplusplus)
extern "C" {
#endif

struct dirent {
    char d_name[260];
};
typedef struct atfw_dir DIR;

DIR *opendir(const char *);
struct dirent *readdir(DIR *);
int closedir(DIR *);

#if defined(__cplusplus)
}
#endif
#endif
