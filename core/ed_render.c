/* ed_render.c - part of editor.c (included by it, not compiled on its own): status line and screen rendering */
#if !defined(M_ASM) || defined(C_RENDER)   /* the Z80 build has all of this in hal/screen_z80.asm (CRENDER=1 bz_build.sh: keep the C, as a reference for screen comparisons) */
/* ------------------------------------------------------------ rendering */
void putnum(u8 *dst, pos_t v, u8 *w)
{
    u8 tmp[11];
    static u8 i, n;
    n = 0;
    do { tmp[n++] = (u8)('0' + v % 10); v = (pos_t)(v / 10); } while (v);
    for (i = 0; i < n; i++) dst[i] = tmp[n - 1 - i];
    *w = n;
}

static void put_str(u8 *row, u8 col, const char *s)
{
    while (*s && col < COLS) row[col++] = (u8)*s++;
}

pos_t lineno(pos_t p)          /* 1-based line number of the line containing p (cached, incremental) */
{
    if (lc_pos > p) lc_line = (pos_t)(lc_line - count_nl(p, lc_pos));
    else lc_line = (pos_t)(lc_line + count_nl(lc_pos, p));
    lc_pos = p;
    return lc_line;
}

static void build_status(void)
{
    static u8 i, n, c;
    pos_t line, col, curs;
    static u8 at;
    const char *m;
    for (i = 0; i < COLS; i++) { rowc[i] = ' '; }
    if (mode == M_CMD) {
        at = (u8)(AT_RV | S_CMD);
        rowc[0] = cmdch;
        for (i = 0; i < cmdlen && (u8)(i + 1) < COLS; i++) rowc[i + 1] = cmdbuf[i];
    } else {
        at = (u8)(AT_RV | (mode == M_INSERT ? S_INSERT : mode == M_VISUAL ? S_CMD : S_NORMAL));
        m = mode == M_INSERT ? "-- INSERT --" : mode == M_VISUAL ? (vblk ? "-- V-BLOCK --" : vline ? "-- V-LINE --" : "-- VISUAL --") : "NORMAL";
        put_str(rowc, 0, m);
        if (mrc) rowc[12] = mrc;
        if (msg[0]) put_str(rowc, 14, msg);
        else {
            put_str(rowc, 14, fname[0] ? fname : "[No Name]");
            if (modified) put_str(rowc, (u8)(14 + 14), "[+]");
        }
        /* line,col at the right */
        curs = cur;
        line = lineno(curs);
        col = (pos_t)(curs - lstart(curs) + 1);
        putnum(rowc + 64, line, &n);
        c = (u8)(64 + n);
        rowc[c++] = ',';
        putnum(rowc + c, col, &n);
    }
    for (i = 0; i < COLS; i++) rowa[i] = at;
}

#ifdef R_ASM
extern u16 rowhash(const u8 *row);             /* render_z80.asm */
extern void rowfix(u8 *row, u8 n);
extern u16 rowh2;
#else
static u16 rowh2;
static u16 rowhash(const u8 *row)
{
    u16 h1 = 0, h2 = 0;
    u8 x;
    for (x = 0; x < COLS; x++) { h1 = (u16)(h1 + row[x]); h2 = (u16)(h2 + h1); }
    rowh2 = h2;
    return h1;
}
static void rowfix(u8 *row, u8 n) { while (n--) { if (*row < 0x20) *row = ' '; row++; } }
#endif

static void flushrow(u8 y, u8 sig)
{
    static u16 h1, h2;
    h1 = rowhash(rowc);
    h2 = rowh2;
    if (!shvalid || sig == 0xFD || sh_sig[y] != sig || sh_h1[y] != h1 || sh_h2[y] != h2) {
        sh_h1[y] = h1; sh_h2[y] = h2;
        sh_sig[y] = sig;
        hal_putrow(y, rowc, rowa);
    }
}

static void shadow_scroll(int n)     /* mirror a hardware scroll of n lines in the shadow screen */
{
    static u8 y;
    if (n > 0) {
        for (y = 0; y + n <= ROWS; y++) { sh_h1[y] = sh_h1[y + n]; sh_h2[y] = sh_h2[y + n]; sh_sig[y] = sh_sig[y + n]; }
        for (y = (u8)(ROWS - n); y <= ROWS; y++) sh_sig[y] = 0xFE;
    } else {
        for (y = ROWS; y >= (u8)(-n); y--) { sh_h1[y] = sh_h1[y + n]; sh_h2[y] = sh_h2[y + n]; sh_sig[y] = sh_sig[y + n]; }
        for (y = 0; y < (u8)(-n); y++) sh_sig[y] = 0xFE;
        sh_sig[ROWS] = 0xFE;     /* status row is now in the wrong place */
    }
}

void ed_render(void)
{
    pos_t s, p, e, rel, k, len, oldtop;
    static u16 col, curcol;
    static u8 y, x, sig, nw, i;
    static u16 tw, ln, v;
    pos_t curs, vs, ve;
    int scr;

    nw = nu ? 5 : 0;
    tw = (u16)(COLS - nw);

    /* vertical scroll: keep the cursor line inside [top, top+ROWS) */
    curs = lstartc();
    oldtop = top;
    scr = 0;
    if (curs < top) {
        top = curs;
        if (oldtop > tlen()) oldtop = tlen();          /* the text may have shrunk below the old top */
        p = count_nl(top, oldtop);
        scr = p >= ROWS ? -ROWS : -(int)p;
    }
    rel = count_nl(top, curs);
    if (rel >= ROWS) {
        if (rel > (pos_t)(ROWS + 16)) {                 /* far jump: find the top line by number, not line by line */
            top = tx_nthline((pos_t)(lineno(curs) - (ROWS - 1)));
            scr = ROWS;
        } else while (rel >= ROWS) { top = (pos_t)(lend(top) + 1); rel--; if (scr < ROWS) scr++; }
    }
    curcol = (u16)(cur - curs);
    if (curcol < left) left = curcol;
    if (curcol >= (u16)(left + tw)) left = (u16)(curcol - tw + 1);

    if (shvalid && scr != 0) {
        if (scr > -ROWS && scr < ROWS) { hal_scroll(scr); shadow_scroll(scr); }
        else shvalid = 0;
    }

    s = top;
    len = tlen();
    vs = ve = 0;
    if (mode == M_VISUAL) { vis_range(&vs, &ve); if (vblk) blkgeom(); }   /* (the block's columns: bc1..bc2) */
    if (nu) ln = (u16)lineno(top);
    for (y = 0; y < ROWS; y++) {
        memset(rowc, ' ', COLS);
        memset(rowa, AT_WHITE, COLS);
        sig = 0xFF;
        if (s >= len) {
            rowc[0] = '~';
        } else {
            e = lend(s);
            k = (pos_t)(s + left);
            if (k < e) {
                x = (u8)((pos_t)(e - k) > tw ? tw : (u8)(e - k));
                tx_read(rowc + nw, k, x);
                rowfix(rowc + nw, x);
            }
            if (s == curs) {
                col = (u16)(curcol - left);
                if (col < tw) { rowa[col + nw] = (u8)(AT_WHITE | AT_RV); sig = (u8)col; }
            }
            if (ve > vs && ve > s) {            /* visual selection highlight (offsets within the line) */
                u16 a = vs > s ? (u16)(vs - s) : 0, b = (u16)(e + 1 - s), l16 = (u16)left;
                if (ve < (pos_t)(e + 1)) b = (u16)(ve - s);
                if (vblk) { a = bc1; b = (u16)(bc2 + 1); if (b > (u16)(e - s)) b = (u16)(e - s); }
                for (; a < b; a++)
                    if (a >= l16 && a < (u16)(l16 + tw)) { rowa[a - l16 + nw] = (u8)(AT_WHITE | AT_RV); sig = 0xFD; }
            }
            if (nu) {                           /* line number gutter: 4 digits + space */
                i = 4;
                v = ln++;
                do { rowc[--i] = (u8)('0' + v % 10); v /= 10; } while (v && i);
            }
            s = (pos_t)(e + 1);
        }
        flushrow(y, sig);
    }
    build_status();
    flushrow(ROWS, rowa[0]);
    shvalid = 1;
}
#endif
