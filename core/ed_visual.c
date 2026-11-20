/* ed_visual.c - part of editor.c (included by it, not compiled on its own): visual mode (v V Ctrl-V) */
/* ------------------------------------------------------------ visual mode */
#ifndef M_ASM                 /* the Z80 build has vis_range / vis_motion / visual_key in hal/visual_z80.asm */
static void vis_range(pos_t *ps, pos_t *pe)
{
    pos_t a, b;
    a = vstart < cur ? vstart : cur;
    b = vstart < cur ? cur : vstart;
    if (vline || vblk) { a = lstart(a); b = (pos_t)(lend(b) + 1); }
    else b = (pos_t)(b + 1);
    if (b > tlen()) b = tlen();
    *ps = a; *pe = b;
}

static u8 vis_motion(u8 k)
{
    switch (k) {
    case 'h': case 'j': case 'k': case 'l': case '0': case '^': case '$':
    case 'w': case 'b': case 'e': case 'W': case 'B': case 'E': case 'G': case 'g':
    case 'n': case 'N': case '*': case '#': case '%': case 'H': case 'M': case 'L': case '{': case '}':
    case 0x1C: case 0x1D: case 0x1E: case 0x1F:
    case 0x04: case 0x15: case 0x06: case 0x02: case 0x05: case 0x19:
        return 1;
    }
    return (u8)(k >= '1' && k <= '9');
}
#endif

/* ---- Ctrl-V block mode: columns are character offsets in the line (tabs count as one) ---- */
u16 bc1, bc2, bnr;                 /* columns c1..c2, rows */
pos_t btop;                        /* start of the top row */
#ifdef M_ASM                 /* the Z80 build has the block code in hal/block_z80.asm */
void blkgeom(void); void blkop(u8 k) FASTCALL;
#else
static void blkgeom(void)
{
    static pos_t p, q;
    static u16 a, b;
    p = vstart < cur ? vstart : cur;
    q = vstart < cur ? cur : vstart;
    btop = lstart(p);
    a = (u16)(vstart - lstart(vstart));
    b = (u16)(cur - lstart(cur));
    bc1 = a < b ? a : b; bc2 = a < b ? b : a;
    bnr = (u16)(lineno(lstart(q)) - lineno(btop) + 1);
}
static void blkseg(pos_t ls, pos_t *a, pos_t *b)       /* the block's part of the line at ls */
{
    static pos_t le;
    le = lend(ls);
    *a = (pos_t)(ls + bc1); if (*a > le) *a = le;
    *b = (pos_t)(ls + bc2 + 1); if (*b > le) *b = le;
}
static void blkpad(pos_t ls, u16 col)                  /* make the line at ls at least col characters long */
{
    while ((u16)(lend(ls) - ls) < col) if (!tins(lend(ls), ' ')) return;
}
void blkop(u8 k) FASTCALL
{
    static pos_t ls, a, b;
    static u16 i, m;
    blkgeom();
    mode = M_NORMAL;
    if (k == 'd' || k == 'x' || k == 'c' || k == 's') {
        for (i = bnr; i; i--) {                                 /* delete from the bottom row up */
            ls = btop;
            for (m = 1; m < i && ls < tlen(); m++) ls = (pos_t)(lend(ls) + 1);
            if (ls >= tlen()) continue;
            blkseg(ls, &a, &b);
            if (b > a) tdel(a, (pos_t)(b - a));
        }
        if (k == 'd' || k == 'x') { cur = (pos_t)(btop + bc1); sethcur(cur); return; }
        k = 'I';
    }
    blkpad(btop, (u16)(k == 'A' ? bc2 + 1 : bc1));
    cur = (pos_t)(btop + (k == 'A' ? bc2 + 1 : bc1));
    bkn = (u16)(bnr - 1); bkc = (u16)(cur - btop); bka = (u8)(k == 'A');
    begin_ins('i', 1);
}
void blkrep(void)                  /* leaving a block I / A: the typed text goes into the other rows too */
{
    static pos_t ls;
    static u16 len, i, n;
    n = bkn; bkn = 0;
    if (cur <= istart || (u16)(cur - istart) > ISZ) return;
    len = (u16)(cur - istart);
    for (i = 0; i < len; i++) { ibuf[i] = tget((pos_t)(istart + i)); if (ibuf[i] == '\n') return; }
    ls = (pos_t)(lend(lstartc()) + 1);
    while (n-- && ls < tlen()) {
        if (!bka && (u16)(lend(ls) - ls) < bkc) { ls = (pos_t)(lend(ls) + 1); continue; }
        blkpad(ls, bkc);
        if (!tinsn((pos_t)(ls + bkc), ibuf, len)) return;
        ls = (pos_t)(lend(ls) + 1);
    }
}
#endif
u8 vp;                         /* visual mode: i or a typed, waiting for the object */
#ifndef M_ASM
void visual_key(u8 k) FASTCALL
{
    static pos_t s, e, t;
    static u8 op, lin;
    if (vp) { op = vp; vp = 0; if (k != 0x1B) { textobj('v', op, k); return; } }
    if (pend || count) { normal_key(k); return; }
    if (k == 0x1B) { mode = M_NORMAL; return; }
    if (k == 'i' || k == 'a') { vp = k; return; }
    if (k == 'v') { if (vline || vblk) vline = vblk = 0; else mode = M_NORMAL; return; }
    if (k == 'V') { if (!vline || vblk) { vline = 1; vblk = 0; } else mode = M_NORMAL; return; }
    if (k == 0x16) { if (vblk) mode = M_NORMAL; else { vblk = 1; vline = 0; } return; }
    if (vblk && (k == 'd' || k == 'x' || k == 'c' || k == 's' || k == 'I' || k == 'A')) { blkop(k); return; }
    if (k == 'o') { t = cur; cur = vstart; vstart = t; setwant(); return; }
    op = 0; lin = vline;
    switch (k) {
    case 'd': case 'x': op = 'd'; break;
    case 'X': case 'D': op = 'd'; lin = 1; break;
    case 'y': op = 'y'; break;
    case 'Y': op = 'y'; lin = 1; break;
    case '>': case '<': op = k; lin = 1; break;
    case 'c': case 's': op = 'c'; break;
    case 'u': case 'U': case '~': op = k; break;
    case 'C': case 'S': case 'R': op = 'c'; lin = 1; break;
    default: break;
    }
    if (op) {
        u8 sv = vline;
        vline = lin;
        vis_range(&s, &e);
        vline = sv;
        mode = M_NORMAL;
        gs = s; ge = e; glin = lin; op_apply(op);
        return;
    }
    if (vis_motion(k)) normal_key(k);
}
#endif
