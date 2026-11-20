/* ed_move.c - part of editor.c (included by it, not compiled on its own): cursor helpers: lines, paragraphs, words */
/* ------------------------------------------------------------ cursor helpers */
#ifndef M_ASM
static void setwant(void) { want = (pos_t)(cur - lstartc()); }

static void clampcur(void)
{
    pos_t s, e;
    if (cur >= tlen()) cur = (pos_t)(tlen() - 1);
    if (mode != M_INSERT) {
        s = lstartc();
        e = lendc();
        if (cur >= e && e > s) cur = (pos_t)(e - 1);
    }
}

static void sethcur(pos_t p)
{
    cur = p;
    clampcur();
    setwant();
}

static pos_t lmove(pos_t p, u8 down)         /* start of the line below/above the line starting at p, or POS_NONE */
{
    if (down) {
        p = lend(p);
        return (pos_t)(p + 1) >= tlen() ? POS_NONE : (pos_t)(p + 1);
    }
    return p == 0 ? POS_NONE : lstart((pos_t)(p - 1));
}

static pos_t lmoven(pos_t p, u16 n, u8 down)  /* n lines down/up, or POS_NONE if there are not that many */
{
    while (n-- && p != POS_NONE) p = lmove(p, down);
    return p;
}

static pos_t para(u16 n, u8 down)             /* { } : the blank line n paragraphs away (or the end/start of the text) */
{
    pos_t p = lstartc(), q;
    static u8 seen;
    while (n--) {
        seen = 0;
        for (;;) {
            if (lend(p) != p) seen = 1;
            else if (seen) break;
            q = lmove(p, down);
            if (q == POS_NONE) return down ? lend(p) : p;
            p = q;
        }
    }
    return p;
}

static void vmove(u16 n, u8 down)
{
    static pos_t s, e;
    static u16 len, col;
    s = lstartc();
    while (n-- && (e = lmove(s, down)) != POS_NONE) s = e;
    e = lend(s);
    len = (u16)(e - s);
    col = want;
    if (mode == M_INSERT) {
        if (col > len) col = len;
    } else if (len == 0) col = 0;
    else if (col >= len) col = (u16)(len - 1);
    cur = (pos_t)(s + col);
}

#endif
u8 bigw;                  /* W B E: a word is any run of non-blanks */
#ifndef M_ASM
static u8 cls(u8 c)
{
    if (c == ' ' || c == '\n' || c == '\t') return 0;
    if (bigw) return 1;
    if ((c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_' || c >= 0xA0)
        return 1;
    return 2;
}
#endif

#ifdef U_ASM
pos_t skipf(pos_t p, pos_t end, u8 c);
pos_t skipb(pos_t p, u8 c, u8 o);
#else
static pos_t skipf(pos_t p, pos_t end, u8 c) { while (p < end && cls(tget(p)) == c) p++; return p; }
static pos_t skipb(pos_t p, u8 c, u8 o) { while (p > 0 && cls(tget((pos_t)(p - o))) == c) p--; return p; }
#endif

#ifndef M_ASM
static pos_t nextword(pos_t p)
{
    pos_t len;
    static u8 c;
    len = tlen();
    c = cls(tget(p));
    if (c) p = skipf(p, len, c);
    return skipf(p, len, 0);
}

static pos_t endword(pos_t p, u16 n)     /* index of the last character of the n-th word end from p */
{
    pos_t len;
    static u8 c;
    len = tlen();
    while (n--) {
        if (p + 1 < len) p++;
        p = skipf(p, (pos_t)(len - 1), 0);
        c = cls(tget(p));
        p = (pos_t)(skipf((pos_t)(p + 1), len, c) - 1);
    }
    return p;
}

static pos_t backword(pos_t p, u16 n)
{
    static u8 c;
    while (n-- && p > 0) {
        p--;
        p = skipb(p, 0, 0);
        c = cls(tget(p));
        p = skipb(p, c, 1);
    }
    return p;
}

static void wordfwd(u16 n)
{
    static pos_t p, len;
    p = cur;
    len = tlen();
    while (n--) {
        p = nextword(p);
        if (p >= len) { p = (pos_t)(len - 1); break; }
    }
    sethcur(p);
}

static void wordback(u16 n)
{
    sethcur(backword(cur, n));
}

static void gotoline(pos_t n)       /* 1-based; beyond the end = last line */
{
    sethcur(tx_nthline(n));
}
#endif
