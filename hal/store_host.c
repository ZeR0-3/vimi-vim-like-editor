/* store_host.c - text store in plain RAM for the PC tests */
#include <string.h>
#include "store.h"
#ifndef HOST_CAP
#define HOST_CAP 30000u
#endif
static u8 mem[HOST_CAP];
void st_init(void) {}
void st_exit(void) {}
pos_t  st_cap(void) { return HOST_CAP; }
u8   st_get(pos_t i) { return mem[i]; }
void st_put(pos_t i, u8 c) { mem[i] = c; }
void st_read(u8 *dst, pos_t src, pos_t n) { memcpy(dst, mem + src, n); }
void st_write(pos_t dst, const u8 *src, pos_t n) { memcpy(mem + dst, src, n); }
void st_move(pos_t dst, pos_t src, pos_t n) { memmove(mem + dst, mem + src, n); }
pos_t st_findb(pos_t off, pos_t end, u8 c)
{
    pos_t i;
    for (i = off; i < end; i++) if (mem[i] == c) return i;
    return end;
}
pos_t st_rfindb(pos_t off, pos_t floor, u8 c)
{
    pos_t i;
    for (i = off; i > floor; i--) if (mem[i - 1] == c) return (pos_t)(i - 1);
    return POS_NONE;
}
pos_t st_countb(pos_t off, pos_t end, u8 c)
{
    pos_t i, n = 0;
    for (i = off; i < end; i++) if (mem[i] == c) n++;
    return n;
}
void st_close(void) {}
void st_select(char d, u16 kb) { (void)d; (void)kb; }
