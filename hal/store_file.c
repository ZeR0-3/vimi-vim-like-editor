/* store_file.c - text store in a swap file (BDOS random access) with a small RAM cache.
 * Use it on a fast drive (E: EMM, F: RAM disk).  Selected at run time:  VIMI -sE file  (60KB)  or  -sE256 file  (256KB).
 * Block = 1KB (8 records), cache = 8 blocks, write-back.  Offsets are 32 bit (pos_t); capacity = KB*1024 (max 1MB-1KB). */
#include <cpm.h>
#include "store.h"

#define BSZ    1024
#define NSLOT  4
#define BDOS_CLOSE  16
#define BDOS_DELETE 19
#define BDOS_WRSEQ  21
#define BDOS_MAKE   22
#define BDOS_DMA    26
#define BDOS_RDRND  33
#define BDOS_WRRND  34

extern u8 st_mem;
extern void st_saveorig(void);

/* The cache lives in TPA RAM above the program image, A000h-AFFFh (NOT in BSS: the image must stay below A000h, which is
 * the bank window of the page store; this store never opens the window, so A000h is plain RAM here). */
#define SLOT(i) ((u8 *)(0xA000u + ((u16)(i) << 10)))
extern u16 sblk[NSLOT];            /* the cache state and the data path are in store_file_z80.asm */
extern u8 sdirty[NSLOT];
extern u8 rr, lasti;
extern u8 sfcb[36];
static pos_t capacity;

u8 stf_init(char d, u16 kb)
{
    u16 r, nrec;
    u8 i;
    if (kb == 0) kb = 60;
    if (kb > 1023) kb = 1023;
    if (d >= 'a' && d <= 'z') d = (char)(d - 32);
    for (i = 0; i < 36; i++) sfcb[i] = 0;
    sfcb[0] = (u8)(d - 'A' + 1);
    for (i = 1; i < 12; i++) sfcb[i] = ' ';
    sfcb[1] = 'V'; sfcb[2] = 'I'; sfcb[3] = 'M'; sfcb[4] = 'I';
    sfcb[5] = 'S'; sfcb[6] = 'W'; sfcb[7] = 'P'; sfcb[9] = 'T'; sfcb[10] = 'M'; sfcb[11] = 'P';
    bdos(BDOS_DELETE, (int)sfcb);
    for (i = 12; i < 36; i++) sfcb[i] = 0;
    if ((bdos(BDOS_MAKE, (int)sfcb) & 0xFF) == 0xFF) return 0;
    { u16 z; u8 *q = SLOT(0); for (z = 0; z < 128; z++) q[z] = 0; }
    bdos(BDOS_DMA, (int)SLOT(0));
    nrec = (u16)(kb * 8);
    for (r = 0; r < nrec; r++) {          /* pre-allocate: a full disk fails now, not in the middle of editing */
        if (bdos(BDOS_WRSEQ, (int)sfcb) & 0xFF) {
            bdos(BDOS_CLOSE, (int)sfcb);
            bdos(BDOS_DELETE, (int)sfcb);
            return 0;
        }
    }
    for (i = 0; i < NSLOT; i++) { sblk[i] = 0xFFFF; sdirty[i] = 0; }
    rr = 0; lasti = 0;
    st_saveorig();
    capacity = (pos_t)kb * BSZ;
    st_mem = 2;
    return 1;
}

pos_t stf_cap(void) { return capacity; }

void stf_exit(void)
{
    bdos(BDOS_CLOSE, (int)sfcb);
    bdos(BDOS_DELETE, (int)sfcb);
}
