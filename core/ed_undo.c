/* ed_undo.c - part of editor.c (included by it, not compiled on its own): the undo / redo log and the logged text primitives */
/* ------------------------------------------------------------ undo / redo log
 * Every edit is recorded as INS(pos,len,data) or DEL(pos,len,data).  Entries made by one normal-mode command
 * (including a whole insert session) share a group id; u undoes a group, Ctrl-R redoes it.
 * Log 0 = undo, log 1 = redo.  When full, the oldest groups are dropped. */
#define UE 24
#define UD 512
#define UOFF(L) (YSZ + (u16)(L) * UD)      /* undo data of log L lives in the aux area */
#define NOAUX 0xFFFFu
#define T_INS 0
#define T_DEL 1
u8  u_typ[2][UE];
pos_t u_pos[2][UE];
u16 u_len[2][UE], u_off[2][UE];   /* small values: keep them 16 bit (BSS size) */
u8  u_grp[2][UE];
u8  u_n[2];
u16 u_dn[2];
u8  ugrp;             /* current group id */
u8  chg;              /* set when the running command edited the text */

#ifdef U_ASM
void ulog_shift(u8 L, u8 k, u16 cut);
u16 ulog_merge(pos_t p);
void ulog_put(u8 L, u8 typ, pos_t pos, u16 len, u8 grp);
#endif
u16 ud[2];                /* 0x100 | group: that group no longer fits in the log, so it is dropped as a whole */
u8  uwarn;                /* a change was too big for the undo log: tell the user once the command is done */
const char m_noundo[] = "too big: cannot undo";
static void ulog_clear(void) { u_n[0] = u_n[1] = 0; u_dn[0] = u_dn[1] = 0; ud[0] = ud[1] = 0; }

#ifndef M_ASM
static void ulog_drop_oldest(u8 L)
{
    static u8 k, i, g;
    static u16 cut;
    g = u_grp[L][0];
    k = 1;
    while (k < u_n[L] && u_grp[L][k] == g) k++;
    if (k >= u_n[L]) { u_n[L] = 0; u_dn[L] = 0; return; }
    cut = u_off[L][k];
    tx_aux_move(UOFF(L), (u16)(UOFF(L) + cut), (u16)(u_dn[L] - cut));
    u_dn[L] = (u16)(u_dn[L] - cut);
#ifdef U_ASM
    ulog_shift(L, k, cut);
#else
    for (i = k; i < u_n[L]; i++) {
        u_typ[L][i - k] = u_typ[L][i];
        u_pos[L][i - k] = u_pos[L][i];
        u_len[L][i - k] = u_len[L][i];
        u_off[L][i - k] = (u16)(u_off[L][i] - cut);
        u_grp[L][i - k] = u_grp[L][i];
    }
#endif
    u_n[L] = (u8)(u_n[L] - k);
}

/* add an entry.  Data comes from RAM (src), from the aux area (src==0, aoff) or from the text at pos (src==0, aoff==NOAUX; for
 * deletions, call before deleting) */
void ulog_add(u8 L, u8 typ, pos_t pos, pos_t len32, const u8 *src, u16 aoff, u8 grp)
{
    static u16 i, m, d, len;
    if (ud[L] == (u16)(grp | 0x100)) return;
    len = (u16)len32;
    while (len32 > UD || u_n[L] >= UE || (u16)(u_dn[L] + len) > UD) {
        if (len32 > UD || u_n[L] == 0 || (u_grp[L][0] == grp && u_grp[L][u_n[L] - 1] == grp)) {
            u_n[L] = 0; u_dn[L] = 0;
            ud[L] = (u16)(grp | 0x100);           /* this group no longer fits: forget it entirely */
            if (L == 0) uwarn = 1;
            return;
        }
        ulog_drop_oldest(L);
    }
#ifdef U_ASM
    ulog_put(L, typ, pos, len, grp);
#else
    u_typ[L][u_n[L]] = typ;
    u_pos[L][u_n[L]] = pos;
    u_len[L][u_n[L]] = len;
    u_off[L][u_n[L]] = u_dn[L];
    u_grp[L][u_n[L]] = grp;
#endif
    d = (u16)(UOFF(L) + u_dn[L]);
    if (src) tx_aux_put(d, src, len);
    else if (aoff != NOAUX) tx_aux_move(d, aoff, len);
    else for (i = 0; i < len; i += m) {
        m = len - i > ISZ ? ISZ : len - i;
        tx_read(xb, (pos_t)(pos + i), m);
        tx_aux_put((u16)(d + i), xb, m);
    }
    u_dn[L] = (u16)(u_dn[L] + len);
    u_n[L]++;
}

#ifdef U_ASM
static void ulog_ins1(pos_t p, u8 c)         /* a typed character: coalesce into the previous INS */
{
    u16 d;
    u_n[1] = 0; u_dn[1] = 0;               /* a new edit invalidates redo */
    d = ulog_merge(p);
    if (d) { tx_aux_put((u16)(UOFF(0) + d), &c, 1); return; }
    ulog_add(0, T_INS, p, 1, &c, 0, ugrp);
}
#else
static void ulog_ins1(pos_t p, u8 c)
{
    u8 n;
    u_n[1] = 0; u_dn[1] = 0;               /* a new edit invalidates redo */
    n = u_n[0];
    if (n > 0 && u_typ[0][n - 1] == T_INS && u_grp[0][n - 1] == ugrp
        && (pos_t)(u_pos[0][n - 1] + u_len[0][n - 1]) == p
        && (pos_t)(u_off[0][n - 1] + u_len[0][n - 1]) == u_dn[0] && u_dn[0] < UD) {
        tx_aux_put((u16)(UOFF(0) + u_dn[0]), &c, 1);
        u_dn[0]++;
        u_len[0][n - 1]++;
        return;
    }
    ulog_add(0, T_INS, p, 1, &c, 0, ugrp);
}
#endif

void touched(pos_t p)                  /* bookkeeping after a logged edit at p: line cache, modified flag, redo is void */
{
    if (p < lc_pos) { lc_pos = 0; lc_line = 1; }
    modified = 1;
    chg = 1;
    u_n[1] = 0; u_dn[1] = 0;
}
#endif

static void lc_reset(void) { lc_pos = 0; lc_line = 1; }

#define MKNONE ((pos_t)~(pos_t)0)
pos_t mk[27];
#define jprev mk[26]                          /* where the last jump (G gg / n N * # % marks) started: '' and `` */                                /* marks a-z (POS_NONE = unset), kept in step with edits */
#ifdef U_ASM
void madj(pos_t p, pos_t n, u8 ins);
#else
static void madj(pos_t p, pos_t n, u8 ins)
{
    u8 i;
    for (i = 0; i < 27; i++) {
        pos_t m = mk[i];
        if (m == MKNONE) continue;
        if (ins) { if (m >= p) mk[i] = (pos_t)(m + n); }
        else if (m >= (pos_t)(p + n)) mk[i] = (pos_t)(m - n);
        else if (m > p) mk[i] = p;
    }
}
#endif
#ifndef M_ASM
u8 mins(pos_t p, const u8 *d, pos_t n) { if (!tx_ins(p, d, n)) return 0; madj(p, n, 1); return 1; }
static void mdel(pos_t p, pos_t n) { tx_del(p, n); madj(p, n, 0); }

u8 tins(pos_t p, u8 c)
{
    if (!mins(p, &c, 1)) { setmsg(m_full); return 0; }
    touched(p);
    ulog_ins1(p, c);
    return 1;
}

u8 tinsn(pos_t p, const u8 *d, pos_t n)   /* insert n bytes (logged) */
{
    if (!mins(p, d, n)) { setmsg(m_full); return 0; }
    touched(p);
    ulog_add(0, T_INS, p, n, d, 0, ugrp);
    return 1;
}

void tdel(pos_t p, pos_t n)
{
    ulog_add(0, T_DEL, p, n, 0, NOAUX, ugrp);       /* saves the text first */
    mdel(p, n);
    touched(p);
}

static void raw_del(pos_t p, pos_t n)
{
    mdel(p, n);
    modified = 1;
    lc_reset();
}

static void raw_ins(pos_t p, u16 aoff, u16 n)      /* insert n bytes taken from the aux area */
{
    static u16 i, m;
    for (i = 0; i < n; i += m) {
        m = n - i > ISZ ? ISZ : n - i;
        tx_aux_get(xb, (u16)(aoff + i), m);
        if (!mins((pos_t)(p + i), xb, m)) { setmsg(m_full); break; }
    }
    modified = 1;
    lc_reset();
}

#endif
/* fast scanning */
#define fwd_find(p, end, c) tx_find(p, end, c)
#define back_find(p, c) tx_rfind(p, c)
#define count_nl(a, b) tx_count(a, b, '\n')

#ifndef M_ASM
static pos_t lstart(pos_t p)
{
    static pos_t q;
    q = back_find(p, '\n');
    return q == POS_NONE ? 0 : (pos_t)(q + 1);
}

static pos_t lend(pos_t p)            /* index of the '\n' that ends the line containing p */
{
    return fwd_find(p, tlen(), '\n');
}
static pos_t lstartc(void) { return lstart(cur); }
static pos_t lendc(void) { return lend(cur); }
static u8 tgetc(void) { return tget(cur); }
#endif

#ifndef M_ASM
void keepinvariant(void)
{
    if (tlen() == 0) tins(0, '\n');
    if (cur >= tlen()) cur = lstart((pos_t)(tlen() - 1));
}
#endif
