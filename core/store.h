/* store.h - the text store: a flat byte array of st_cap() bytes (host: plain RAM; MZ-2500: banked RAM pages
 * seen through one 8KB window).  The editor's gap buffer lives in it, addressed by 16bit offsets. */
#ifndef MZV_STORE_H
#define MZV_STORE_H
#include "types.h"
void st_select(char drive, u16 kb);                      /* optional, before st_init: swap file on this drive letter, kb KB (0 = default) */
void st_init(void);                                      /* before everything else */
void st_exit(void);                                      /* before returning to the OS */
pos_t  st_cap(void);                                       /* capacity in bytes */
u8   st_get(pos_t i);
void st_put(pos_t i, u8 c);
void st_read(u8 *dst, pos_t src, pos_t n);                   /* store -> main memory */
void st_write(pos_t dst, const u8 *src, pos_t n);            /* main memory -> store */
void st_move(pos_t dst, pos_t src, pos_t n);                   /* memmove inside the store */
void st_close(void);                                     /* release the bank window before calling the OS */
/* byte search helpers (fast on the Z80: CPIR/CPDR inside the window) */
pos_t  st_findb(pos_t off, pos_t end, u8 c);                   /* first index in [off,end) holding c, else end */
pos_t  st_rfindb(pos_t off, pos_t floor, u8 c);                /* last index in [floor,off) holding c, else POS_NONE */
pos_t  st_countb(pos_t off, pos_t end, u8 c);                  /* number of c in [off,end) */
#endif
