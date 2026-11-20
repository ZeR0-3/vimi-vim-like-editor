/* fs.h - file access. Core sees plain text with '\n' only; the backend converts CRLF/^Z. */
#ifndef MZV_FS_H
#define MZV_FS_H
#include "types.h"
pos_t fs_load(const char *name, pos_t max);                   /* load into the store at offset 0; bytes read, or FS_NOFILE (POS_NONE) if the file does not exist */
#define FS_NOFILE POS_NONE
#define FS_TOOBIG (POS_NONE - 1)                                  /* the file does not fit in max bytes (nothing usable was loaded) */
/* stream a file's text (CRLF->LF, ^Z/NUL end) to sink(buf, n) in chunks of up to 128 bytes. 0 = ok, 1 = no such file, 2 = sink refused */
int fs_stream(const char *name, int (*sink)(const u8 *buf, u8 n));
/* directory listing, one "NAME.EXT\n" per file matching pat (empty = all). 0 = ok, 2 = sink refused */
/* :!cmd support: write VIMICMD.BAT (cmd / pause / V +line file); 0 = ok */
int fs_exec(const char *cmd, u8 wait);                  /* E5h: 0 = done (the child's result), F0h = no 7 free pages, FEh = not available here */
int fs_bat(const char *cmd, const char *file, u16 line);
void fs_erase(const char *name);                              /* delete a file (no error if missing) */
int fs_save(const char *name, pos_t len);                   /* save store[0..len); 0 = ok */
#endif

#ifdef STKDBG
void stk_init(void);
u16 stk_free(void);
#endif
