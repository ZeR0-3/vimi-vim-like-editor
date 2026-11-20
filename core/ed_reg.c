/* ed_reg.c - part of editor.c (included by it, not compiled on its own): yank, named registers and macro storage (the register code lives in bank 6) */
/* ------------------------------------------------------------ edit commands */
/* range scratch shared by get_range / op_apply / yankrange / shift: static longs are cheaper than stack longs or 32-bit arguments on the Z80 */
pos_t gs, ge; static pos_t gp, gq; u8 glin;         /* get_range scratch (static: cheaper than stack longs on the Z80) */
#define s gs
#define e ge
#ifndef M_ASM
void yankrange(void)
{
    static u16 i, n, m;
    if ((pos_t)(e - s) > YSZ) { ylen = 0; setmsg("yank too big"); return; }
    n = (u16)(e - s);
    ynl = 0;
    for (i = 0; i < n; i += m) {
        m = n - i > ISZ ? ISZ : n - i;
        tx_read(xb, (pos_t)(s + i), m);
        tx_aux_put(i, xb, m);
        if (tx_find((pos_t)(s + i), (pos_t)(s + i + m), '\n') < (pos_t)(s + i + m)) ynl = 1;
    }
    ylen = n;
}
#endif
#undef s
#undef e

u8 ylin;                      /* register holds whole lines */

/* named registers a-z ("ayy "Ayy "ap): a 1KB pool in the aux area after the undo logs; the unnamed register (aux offset 0) stays the working copy */
#define RBASE (YSZ + 2 * UD)
#define RSZ   1024
u16 roff[26], rlen[26], rtop;
u8  rflg[26];                    /* bit0 linewise, bit1 holds a line break */
#define MB 80
u16 mc;
u8 ai, ind[33], ilen;             /* :set ai - a new line starts with the indent of the line it came from */
u8  mi, mb[MB], mlen, mrc, mlast, inmac;     /* macro: keys recorded / being played, register being recorded into, last @, playing */
u8  reg, pq;                     /* register chosen with "x; " typed, waiting for the name */
#pragma codeseg code_far
#ifndef M_ASM                 /* the Z80 build has regcompact / regstore in hal/block_z80.asm */
static void regcompact(void)
{
    static u16 nt, bo;
    static u8 j, bj, f;
    nt = 0;
    for (;;) {
        f = 0;
        for (j = 0; j < 26; j++)
            if (rlen[j] && roff[j] >= nt && (!f || roff[j] < bo)) { f = 1; bo = roff[j]; bj = j; }
        if (!f) break;
        if (bo != nt) tx_aux_move((u16)(RBASE + nt), (u16)(RBASE + bo), rlen[bj]);
        roff[bj] = nt;
        nt = (u16)(nt + rlen[bj]);
    }
    rtop = nt;
}
void regstore(const u8 *src, u16 n, u8 f)      /* RAM text src, or the unnamed register if src = 0 -> register reg (an upper-case name appends) */
{
    static u16 i, m, old, tot;
    static u8 r, ap;
    if (!n) return;
    ap = (u8)(reg < 'a');
    r = (u8)((reg | 0x20) - 'a');
    old = ap ? rlen[r] : 0;
    tot = (u16)(old + n);
    if (tot > RSZ) { setmsg(m_full); return; }
    if (rtop + tot > RSZ) regcompact();
    if (rtop + tot > RSZ) { setmsg(m_full); return; }
    if (old) tx_aux_move((u16)(RBASE + rtop), (u16)(RBASE + roff[r]), old);
    for (i = 0; i < n; i += m) {
        m = n - i > ISZ ? ISZ : n - i;
        if (src) tx_aux_put((u16)(RBASE + rtop + old + i), src + i, m);
        else { tx_aux_get(xb, i, m); tx_aux_put((u16)(RBASE + rtop + old + i), xb, m); }
    }
    roff[r] = rtop; rlen[r] = tot; rtop = (u16)(rtop + tot);
    rflg[r] = (u8)((ap ? rflg[r] : 0) | f);
}
#endif
#ifndef M_ASM
static u8 regload(void)                         /* register reg -> the unnamed register, for p P */
{
    static u8 r;
    r = (u8)((reg | 0x20) - 'a');
    if (!rlen[r]) { setmsg("register empty"); return 0; }
    tx_aux_move(0, (u16)(RBASE + roff[r]), rlen[r]);
    ylen = rlen[r]; ylin = (u8)(rflg[r] & 1); ynl = (u8)((rflg[r] >> 1) & 1);
    return 1;
}
#endif
#pragma codeseg code_compiler
