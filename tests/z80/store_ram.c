/* store_ram.c - RAM store for running the text layer under the Z80 emulator (z88dk-ticks) */
#include <string.h>
#include "store.h"
#define CAP 14336u
static u8 mem[CAP];
void st_init(void) {}
void st_exit(void) {}
pos_t st_cap(void) { return CAP; }
u8 st_get(pos_t i) { return mem[(u16)i]; }
void st_put(pos_t i, u8 c) { mem[(u16)i] = c; }
void st_read(u8 *dst, pos_t src, pos_t n) { memcpy(dst, mem + (u16)src, (u16)n); }
void st_write(pos_t dst, const u8 *src, pos_t n) { memcpy(mem + (u16)dst, src, (u16)n); }
void st_move(pos_t dst, pos_t src, pos_t n) { memmove(mem + (u16)dst, mem + (u16)src, (u16)n); }
pos_t st_findb(pos_t off, pos_t end, u8 c)
{
    u16 i;
    for (i = (u16)off; i < (u16)end; i++) if (mem[i] == c) return i;
    return end;
}
pos_t st_rfindb(pos_t off, pos_t floor, u8 c)
{
    u16 i;
    for (i = (u16)off; i > (u16)floor; i--) if (mem[i - 1] == c) return (pos_t)(i - 1);
    return POS_NONE;
}
pos_t st_countb(pos_t off, pos_t end, u8 c)
{
    u16 i, n = 0;
    for (i = (u16)off; i < (u16)end; i++) if (mem[i] == c) n++;
    return n;
}
void st_close(void) {}
void st_select(char d, u16 kb) { (void)d; (void)kb; }
