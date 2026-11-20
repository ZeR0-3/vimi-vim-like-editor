/* text_blk.c - text as a list of 1KB blocks inside the flat store (store.h).
 * An edit only touches the block it lands in (insert/delete shifts at most 1KB; a full block is split, an
 * empty one is dropped), so editing far from the previous edit costs nothing extra, unlike a gap buffer
 * where the gap must be moved across the whole distance (disk I/O in the swap-file store).
 * Order table: bph[0..nb) = physical block of the i-th logical block, blen[] = its used bytes;
 * bph[nb..NB) holds the free physical blocks (so bph is always a permutation of 0..NB-1). */
#include <string.h>
#include "text.h"
#include "store.h"

#define BLK 1024u
#ifndef TX_NBMAX
#define TX_NBMAX 128                 /* blocks: 128KB of text (BSS: 3 bytes per block) */
#endif

#ifdef TX_ASM                         /* the Z80 build reads these from text_z80.asm */
#define EXPORT
#else
#define EXPORT static
#endif
EXPORT u16 blen[TX_NBMAX];
EXPORT u8  bnl[TX_NBMAX];           /* newlines in block i; 0xFF = unknown or >= 255 (counted on demand) */
EXPORT u8  bph[TX_NBMAX];
static u8  hinted;                   /* bnl[] holds exact counts gathered while loading */
EXPORT u16 nb;
static u16 NB;                   /* blocks in use / blocks available */
static pos_t total;                  /* text length */
EXPORT u16 ci;                       /* cache: block index ... */
EXPORT pos_t cs;                     /* ... and the logical offset of its first byte */

#ifdef TX_ASM
pos_t ph(u16 i, u16 off);              /* store address of byte off of logical block i (text_z80.asm) */
#else
static pos_t ph(u16 i, u16 off) { return (pos_t)((pos_t)bph[i] * BLK + off); }
#endif

#ifdef TX_ASM
u16 nlc(u16 i);
void insert_block(u16 at, u16 len);
void remove_block(u16 at);
#else
static u16 nlc(u16 i)                /* newlines in logical block i */
{
    u16 c;
    if (bnl[i] != 0xFF) return bnl[i];
    c = (u16)st_countb(ph(i, 0), ph(i, blen[i]), '\n');
    if (c < 255) bnl[i] = (u8)c;
    return c;
}
#endif

static void setnb(void)
{
    u16 k;
    k = (u16)(st_cap() >> 10);
    k = k > TX_AUX / BLK ? (u16)(k - TX_AUX / BLK) : 0;      /* the last blocks hold the aux area */
    NB = k > TX_NBMAX ? TX_NBMAX : k;
}

static pos_t auxb(void) { setnb(); return (pos_t)((pos_t)NB * BLK); }
void tx_aux_put(u16 off, const u8 *src, u16 n) { st_write((pos_t)(auxb() + off), src, n); }
void tx_aux_get(u8 *dst, u16 off, u16 n) { st_read(dst, (pos_t)(auxb() + off), n); }
void tx_aux_move(u16 dst, u16 src, u16 n) { pos_t b = auxb(); st_move((pos_t)(b + dst), (pos_t)(b + src), n); }

pos_t tx_cap(void) { setnb(); return (pos_t)((pos_t)NB * BLK); }

void tx_adopt(pos_t n)
{
    u16 i, last;
    setnb();
    nb = n ? (u16)((u16)(n >> 10) + (((u16)n & (BLK - 1)) != 0)) : 1;
    last = n ? (u16)((((u16)n - 1) & (BLK - 1)) + 1) : 0;      /* bytes in the last block */
    for (i = 0; i < NB; i++) {
        bph[i] = (u8)i;
        if (!hinted) bnl[i] = 0xFF;
        blen[i] = (u16)(i + 1 < nb ? BLK : (i + 1 == nb ? last : 0));
    }
    total = n;
    ci = 0; cs = 0;
    hinted = 0;
}

void tx_reset(void) { hinted = 0; tx_adopt(0); }

void tx_load_begin(void)
{
    u16 i;
    for (i = 0; i < TX_NBMAX; i++) bnl[i] = 0;
    hinted = 1;
}

void tx_load_chunk(pos_t off, const u8 *buf, u16 k)
{
    u16 b;
    while (k--) {
        if (*buf++ == '\n') {
            b = (u16)((pos_t)off / BLK);
            if (b < TX_NBMAX) bnl[b] = (u8)(bnl[b] >= 0xFE ? 0xFF : bnl[b] + 1);     /* 0xFF stays "count on demand" */
        }
        off = (pos_t)(off + 1);
    }
}
pos_t tx_len(void) { return total; }
pos_t tx_free(void) { return (u16)(NB - nb) >= 2 ? (pos_t)((pos_t)(NB - nb - 2) * BLK) : 0; }

#ifdef TX_ASM
void locate(pos_t p);
#else
static void locate(pos_t p)           /* ci/cs := the block holding p (p == total: the last block) */
{
    while (ci > 0 && cs > p) { ci--; cs = (pos_t)(cs - blen[ci]); }
    while ((u16)(ci + 1) < nb && p >= (pos_t)(cs + blen[ci])) { cs = (pos_t)(cs + blen[ci]); ci++; }
}

u8 tx_get(pos_t i)
{
    locate(i);
    return st_get((pos_t)(ph(ci, 0) + (i - cs)));
}
#endif

void tx_read(u8 *dst, pos_t p, pos_t n)
{
    u16 k, o;
    while (n) {
        locate(p);
        o = (u16)(p - cs);
        k = (u16)(blen[ci] - o);
        if ((pos_t)k > n) k = (u16)n;
        st_read(dst, ph(ci, o), k);
        dst += k; p = (pos_t)(p + k); n = (pos_t)(n - k);
    }
}

#ifndef TX_ASM
static void insert_block(u16 at, u16 len)    /* a new block (taken from the free ones) at logical index at */
{
    u8 ph;
    ph = bph[nb];
    memmove(bph + at + 1, bph + at, (u16)(nb - at));
    memmove(blen + at + 1, blen + at, (u16)((nb - at) * sizeof(blen[0])));
    memmove(bnl + at + 1, bnl + at, (u16)(nb - at));
    bph[at] = ph;
    blen[at] = len;
    bnl[at] = 0xFF;
    nb++;
}

static void remove_block(u16 at)
{
    u8 ph;
    ph = bph[at];
    memmove(bph + at, bph + at + 1, (u16)(nb - at - 1));
    memmove(blen + at, blen + at + 1, (u16)((nb - at - 1) * sizeof(blen[0])));
    memmove(bnl + at, bnl + at + 1, (u16)(nb - at - 1));
    bph[nb - 1] = ph;
    nb--;
}
#endif

static void merge_at(u16 i)                         /* fold block i+1 into i when both fit in one block */
{
    u16 a;
    if ((u16)(i + 1) < nb && (u16)((a = blen[i]) + blen[i + 1]) <= BLK) {
        st_move(ph(i, a), ph((u16)(i + 1), 0), blen[i + 1]);
        blen[i] = (u16)(a + blen[i + 1]);
        bnl[i] = 0xFF;
        remove_block((u16)(i + 1));
    }
}

u8 tx_ins(pos_t p, const u8 *src, pos_t n)          /* n < 64KB */
{
    u16 off, k, tl, bl, m;
    if (n == 0) return 1;
    if (n > 0xFFFFu) return 0;
    m = (u16)n;
    locate(p);
    off = (u16)(p - cs);
    bl = blen[ci];
    if (m <= (u16)(BLK - bl)) {                      /* fits in this block */
        if (off < bl) st_move(ph(ci, (u16)(off + m)), ph(ci, off), (u16)(bl - off));
        st_write(ph(ci, off), src, m);
        blen[ci] = (u16)(bl + m);
        bnl[ci] = 0xFF;
        total = (pos_t)(total + m);
        return 1;
    }
    if ((u16)((m >> 10) + 2) > (u16)(NB - nb)) return 0;
    if (off < bl) {                                  /* move the part after p into a block of its own */
        tl = (u16)(bl - off);
        st_move(ph(nb, 0), ph(ci, off), tl);         /* bph[nb] = the next free physical block (taken by insert_block) */
        insert_block((u16)(ci + 1), tl);
        blen[ci] = off;
        bnl[ci] = 0xFF;
    }
    while (m) {
        k = (u16)(BLK - blen[ci]);
        if (k > m) k = m;
        if (k) {
            st_write(ph(ci, blen[ci]), src, k);
            blen[ci] = (u16)(blen[ci] + k);
            bnl[ci] = 0xFF;
            total = (pos_t)(total + k);
            src += k; m = (u16)(m - k);
        }
        if (m) {
            insert_block((u16)(ci + 1), 0);
            cs = (pos_t)(cs + blen[ci]);
            ci++;
        }
    }
    return 1;
}

void tx_del(pos_t p, pos_t n)
{
    u16 off, k, bl;
    while (n) {
        locate(p);
        off = (u16)(p - cs);
        bl = blen[ci];
        k = (u16)(bl - off);
        if ((pos_t)k > n) k = (u16)n;
        if (k == 0) break;
        if ((u16)(off + k) < bl) st_move(ph(ci, off), ph(ci, (u16)(off + k)), (u16)(bl - off - k));
        blen[ci] = (u16)(bl - k);
        bnl[ci] = 0xFF;
        total = (pos_t)(total - k);
        n = (pos_t)(n - k);
        if (blen[ci] == 0 && nb > 1) {
            remove_block(ci);
            if (ci >= nb) { ci = (u16)(nb - 1); cs = (pos_t)(total - blen[ci]); }
        } else {
            merge_at(ci);
            if (ci > 0 && (u16)(blen[ci - 1] + blen[ci]) <= BLK) { ci--; cs = (pos_t)(cs - blen[ci]); merge_at(ci); }
        }
    }
}

#ifndef TX_ASM
pos_t tx_find(pos_t p, pos_t end, u8 c)
{
    pos_t q, b, lim, off0;
    while (p < end) {
        locate(p);
        b = ph(ci, 0);
        off0 = (pos_t)(p - cs);
        lim = (pos_t)(cs + blen[ci]);
        if (lim > end) lim = end;
        q = st_findb((pos_t)(b + off0), (pos_t)(b + (lim - cs)), c);
        if (q < (pos_t)(b + (lim - cs))) return (pos_t)(cs + (q - b));
        p = lim;
    }
    return end;
}

pos_t tx_rfind(pos_t p, u8 c)
{
    pos_t q, b;
    while (p > 0) {
        locate((pos_t)(p - 1));
        b = ph(ci, 0);
        q = st_rfindb((pos_t)(b + (p - cs)), b, c);
        if (q != POS_NONE) return (pos_t)(cs + (q - b));
        p = cs;
    }
    return POS_NONE;
}

pos_t tx_count(pos_t a, pos_t e, u8 c)
{
    pos_t n, b, lim;
    n = 0;
    while (a < e) {
        locate(a);
        b = ph(ci, 0);
        lim = (pos_t)(cs + blen[ci]);
        if (lim > e) lim = e;
        if (c == '\n' && a == cs && lim == (pos_t)(cs + blen[ci])) n = (pos_t)(n + nlc(ci));   /* whole block: cached */
        else n = (pos_t)(n + st_countb((pos_t)(b + (a - cs)), (pos_t)(b + (lim - cs)), c));
        a = lim;
    }
    return n;
}

#endif

#ifndef TX_ASM
pos_t tx_nthline(pos_t n)            /* start of line n (1-based); beyond the end = the last line */
{
    u16 i, c, o, bl;
    pos_t tot, k, b0, at;
    tot = 0;
    for (i = 0; i < nb; i++) tot = (pos_t)(tot + nlc(i));
    if (tot == 0 || n <= 1) return 0;
    k = (pos_t)(n - 1);
    if (k > (pos_t)(tot - 1)) k = (pos_t)(tot - 1);
    at = 0;
    for (i = 0; i < nb && k; i++) {
        c = nlc(i);
        bl = blen[i];
        if (k <= c) {
            b0 = ph(i, 0);
            o = 0;
            for (c = (u16)k; c; c--) o = (u16)((u16)(st_findb((pos_t)(b0 + o), (pos_t)(b0 + bl), '\n') - b0) + 1);
            return (pos_t)(at + o);
        }
        k = (pos_t)(k - c);
        at = (pos_t)(at + bl);
    }
    return 0;
}
#endif

#ifdef TX_DEBUG
int tx_selfcheck(void)             /* 0 = consistent */
{
    u16 i;
    pos_t s = 0, st = 0;
    for (i = 0; i < nb; i++) { s += blen[i]; if (blen[i] == 0 && nb > 1) return 1; if (blen[i] > BLK) return 4; }
    if (s != total) return 2;
    for (i = 0; i < nb; i++) { if (i == ci) break; st += blen[i]; }
    if (ci >= nb || st != cs) return 3;
    return 0;
}
#endif
#ifdef TX_DEBUG
#include <stdio.h>
void tx_dump(void) { u16 i; printf("nb=%u ci=%u cs=%lu total=%lu:", nb, ci, (unsigned long)cs, (unsigned long)total); for (i = 0; i < nb; i++) printf(" %u(p%u)", blen[i], bph[i]); printf("\n"); }
#endif
