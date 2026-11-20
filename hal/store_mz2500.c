/* store_mz2500.c - text store, C side.  Two back ends behind one interface:
 *   pages / plain memory (store_z80.asm, <= 64KB, 16 bit offsets, bank window)   st_mem = 0 / 1
 *   swap file with RAM cache (store_file.c, 32 bit offsets)                      st_mem = 2
 * Bulk operations in the asm modes go through a 256-byte bounce buffer (one 8KB window only). */
#include "store.h"

extern u16 sv_off, sv_ptr, sv_n;
extern u16 sv_res;
extern u8 sv_c;
extern void sv_findb(void);
extern void sv_rfindb(void);
extern void sv_countb(void);
extern void sv_read(void);
extern void sv_write(void);
extern void st_init_asm(void);
extern void st_exit_asm(void);
extern u16 st_capv;
extern u8 st_get_asm(u16 i) __z88dk_fastcall;
extern u8 st_mem;
extern u8 stf_init(char d, u16 kb);
extern void stf_exit(void);
extern pos_t stf_cap(void);
extern u8 stf_get(pos_t i);
extern void stf_read(u8 *d, pos_t off, pos_t n);
extern void stf_write(pos_t off, const u8 *s, pos_t n);
extern pos_t stf_findb(pos_t off, pos_t end, u8 c);
extern pos_t stf_rfindb(pos_t off, pos_t floor, u8 c);
extern pos_t stf_countb(pos_t off, pos_t end, u8 c);
extern void st_close(void);

static u8 bounce[128];
static u8 one;
static char swapdrv;
static u16 swapkb;

/* st_select('E', 256): swap file on E:, 256KB (0 = 60KB) */
void st_select(char d, u16 kb) { swapdrv = d; swapkb = kb > 128 ? 128 : kb; }   /* the block list holds at most 128 blocks */
void st_init(void)
{
    if (swapdrv && stf_init(swapdrv, swapkb)) return;      /* swap-file store on the chosen drive */
    st_init_asm();                                          /* pages, else plain memory */
}
void st_exit(void)
{
    if (st_mem == 2) stf_exit();
    st_exit_asm();
}
pos_t st_cap(void) { return st_mem == 2 ? stf_cap() : (pos_t)st_capv; }

u8 st_get(pos_t i)
{
    if (st_mem >= 2) return stf_get(i);
    return st_get_asm((u16)i);
}

void st_read(u8 *dst, pos_t src, pos_t n)
{
    if (st_mem >= 2) { stf_read(dst, src, n); return; }
    sv_ptr = (u16)dst; sv_off = (u16)src; sv_n = (u16)n;
    sv_read();
}

void st_write(pos_t dst, const u8 *src, pos_t n)
{
    if (st_mem >= 2) { stf_write(dst, src, n); return; }
    sv_ptr = (u16)src; sv_off = (u16)dst; sv_n = (u16)n;
    sv_write();
}

void st_put(pos_t i, u8 c)
{
    one = c;
    st_write(i, &one, 1);
}

void st_move(pos_t dst, pos_t src, pos_t n)
{
    u16 k;
    if (dst == src || n == 0) return;
    if (dst < src) {
        while (n) {
            k = n > 128 ? 128 : (u16)n;
            st_read(bounce, src, k);
            st_write(dst, bounce, k);
            src += k; dst += k; n -= k;
        }
    } else {
        while (n) {
            k = n > 128 ? 128 : (u16)n;
            n -= k;
            st_read(bounce, (pos_t)(src + n), k);
            st_write((pos_t)(dst + n), bounce, k);
        }
    }
}

pos_t st_findb(pos_t off, pos_t end, u8 c)
{
    if (end <= off) return end;
    if (st_mem >= 2) return stf_findb(off, end, c);
    sv_off = (u16)off; sv_n = (u16)(end - off); sv_c = c;
    sv_findb();
    return sv_res == 0xFFFFu ? end : (pos_t)sv_res;
}

pos_t st_rfindb(pos_t off, pos_t floor, u8 c)
{
    if (off <= floor) return POS_NONE;
    if (st_mem >= 2) return stf_rfindb(off, floor, c);
    sv_off = (u16)(off - 1); sv_n = (u16)(off - floor); sv_c = c;
    sv_rfindb();
    return sv_res == 0xFFFFu ? POS_NONE : (pos_t)sv_res;
}

pos_t st_countb(pos_t off, pos_t end, u8 c)
{
    if (end <= off) return 0;
    if (st_mem >= 2) return stf_countb(off, end, c);
    sv_off = (u16)off; sv_n = (u16)(end - off); sv_c = c;
    sv_countb();
    return (pos_t)sv_res;
}
