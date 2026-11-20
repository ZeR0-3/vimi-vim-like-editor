/* ed_search.c - part of editor.c (included by it, not compiled on its own): regular expressions and / ? n N */
/* ------------------------------------------------------------ command line */

/* Regular expressions for :s (one line at a time): c . [set] [^set] x* \c ^ (start) $ (end) */
pos_t rxb;                          /* start of the line being matched */
u16 rxe;                            /* its length */

u8 icase;
u8 nu;                        /* :set number */                                   /* :set ignorecase (used by the matcher) */
#ifdef U_ASM
#define RXNONE 0xFFFFu
u16 mhere(u8 *re, u16 t);
#else
static u8 *atom_end(u8 *re)
{
    if (re[0] == '\\' && re[1]) return re + 2;
    if (re[0] == '[') {
        u8 *p = re + 1;
        if (*p == '^') p++;
        if (*p == ']') p++;
        while (*p && *p != ']') p++;
        if (*p) return p + 1;
    }
    return re + 1;
}

static u8 fold(u8 c) { return (u8)(icase && c >= 'A' && c <= 'Z' ? c + 32 : c); }

static u8 atom_match(u8 *re, u8 c)
{
    u8 *p, neg, ok;
    c = fold(c);
    if (re[0] == '.') return 1;
    if (re[0] == '\\' && re[1]) return (u8)(c == fold(re[1]));
    if (re[0] != '[' || atom_end(re) == re + 1) return (u8)(c == fold(re[0]));
    p = re + 1;
    neg = (u8)(*p == '^');
    if (neg) p++;
    ok = 0;
    do {
        if (p[1] == '-' && p[2] && p[2] != ']') { if (c >= fold(p[0]) && c <= fold(p[2])) ok = 1; p += 3; }
        else { if (c == fold(p[0])) ok = 1; p++; }
    } while (*p && *p != ']');
    return (u8)(ok != neg);
}

#define RXNONE 0xFFFFu
static u16 mhere(u8 *re, u16 t)             /* match re at offset t of the line: end offset of the match, else RXNONE */
{
    u8 *nx;
    u16 p, q;
    for (;;) {
        if (re[0] == 0) return t;
        if (re[0] == '$' && re[1] == 0) return t == rxe ? t : RXNONE;
        nx = atom_end(re);
        if (*nx == '*') {
            for (p = t; p < rxe && atom_match(re, tget(rxb + p)); p++) ;
            for (;;) {
                q = mhere(nx + 1, p);
                if (q != RXNONE || p == t) return q;
                p--;
            }
        }
        if (t >= rxe || !atom_match(re, tget(rxb + t))) return RXNONE;
        t++;
        re = nx;
    }
}

#endif

/* search: the pattern is a regular expression (same syntax as :s), matched line by line */
u8 *rxpat;
u8 rxanch, rxlit;

#ifdef U_ASM
u16 rx_scan(pos_t ls, u16 lo, u16 hi, u8 back);
#else
static u16 rx_scan(pos_t ls, u16 lo, u16 hi, u8 back)   /* first (or last) match start in [lo,hi] of the line at ls, else RXNONE */
{
    u16 t;
    rxb = ls;
    rxe = (u16)(lend(ls) - ls);
    if (hi > rxe) hi = rxe;
    if (lo > hi) return RXNONE;
    if (rxanch) return (u16)(lo == 0 && mhere(rxpat, 0) != RXNONE ? 0 : RXNONE);
    if (!back) {
        for (t = lo; t <= hi; t++) {
            if (rxlit) {                                   /* first atom is a plain character: jump to its next occurrence */
                pos_t q = fwd_find((pos_t)(rxb + t), (pos_t)(rxb + rxe), rxlit);
                t = (u16)(q - rxb);
                if (t > hi || t >= rxe) break;
            }
            if (mhere(rxpat, t) != RXNONE) return t;
        }
    } else {
        for (t = hi;; t--) {
            if (mhere(rxpat, t) != RXNONE) return t;
            if (t == lo) break;
        }
    }
    return RXNONE;
}
#endif

#ifndef M_ASM
void dosearch(u8 forward) FASTCALL
{
    pos_t ls, ls0;
    u16 c, r;
    if (slen == 0) { setmsg("no search"); return; }
    rxpat = srch;
    rxanch = (u8)(srch[0] == '^');
    if (rxanch) rxpat++;
    rxlit = (u8)(rxpat[0] && rxpat[0] != '.' && rxpat[0] != '[' && rxpat[0] != '\\' && rxpat[0] != '$' && rxpat[1] != '*' ? rxpat[0] : 0);
    ls0 = lstartc();
    c = (u16)(cur - ls0);
    ls = ls0;
    if (forward) {
        r = rx_scan(ls, (u16)(c + 1), 0xFFFF, 0);
        while (r == RXNONE) {
            ls = (pos_t)(lend(ls) + 1);
            if (ls >= tlen()) break;
            r = rx_scan(ls, 0, 0xFFFF, 0);
        }
        if (r == RXNONE) {                           /* wrap around */
            for (ls = 0;; ls = (pos_t)(lend(ls) + 1)) {
                r = rx_scan(ls, 0, ls == ls0 ? c : 0xFFFF, 0);
                if (r != RXNONE || ls >= ls0) break;
            }
        }
    } else {
        r = c ? rx_scan(ls, 0, (u16)(c - 1), 1) : RXNONE;
        while (r == RXNONE && ls > 0) {
            ls = lstart((pos_t)(ls - 1));
            r = rx_scan(ls, 0, 0xFFFF, 1);
        }
        if (r == RXNONE) {
            for (ls = lstart((pos_t)(tlen() - 1));; ls = lstart((pos_t)(ls - 1))) {
                r = rx_scan(ls, ls == ls0 ? c : 0, 0xFFFF, 1);
                if (r != RXNONE || ls <= ls0) break;
            }
        }
    }
    if (r == RXNONE) { setmsg(m_nopat); return; }
    sethcur((pos_t)(ls + r));
}
#endif
