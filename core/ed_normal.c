/* ed_normal.c - part of editor.c (included by it, not compiled on its own): normal mode */
/* ------------------------------------------------------------ normal mode */

#ifdef U_ASM
void casebuf(u8 *p, u8 n, u8 op);
#else
static void casebuf(u8 *p, u8 n, u8 op)
{
    u8 c;
    while (n--) {
        c = *p;
        if ((u8)((c | 0x20) - 'a') < 26 && (op == '~' || (c & 0x20) == (op == 'U' ? 0x20 : 0))) *p = (u8)(c ^ 0x20);
        p++;
    }
}
#endif

#ifndef M_ASM
void casechg(pos_t s, pos_t e, u8 op)   /* ~ u U over [s,e) in chunks (each chunk = one delete + one insert in the undo log) */
{
    static u8 m;
    while (s < e) {
        m = (pos_t)(e - s) > 64 ? 64 : (u8)(e - s);
        tx_read(rowc, s, m);
        casebuf(rowc, m, op);
        tdel(s, m);
        if (!tinsn(s, rowc, m)) break;
        s = (pos_t)(s + m);
    }
}
#endif

#ifndef M_ASM
void case_toggle(u16 n) FASTCALL                 /* ~ */
{
    static u16 r;
    r = (u16)(lendc() - cur);
    if (n > r) n = r;
    if (n == 0) return;
    casechg(cur, (pos_t)(cur + n), '~');
    cur = (pos_t)(cur + n);
    clampcur();
    setwant();
}
#endif

#ifndef M_ASM
void textobj(u8 op, u8 kind, u8 k)
{
    static pos_t s, e, ls, le, q;
    static u8 c, cc, cl;
    ls = lstartc();
    le = lendc();
#ifdef U_ASM
    c = tobj(cur, ls, le, tlen(), kind, k);        /* quotes and brackets: hal/nav_z80.asm (0 = no such object, 1 = range in gs/ge, 2 = not one of those) */
    if (c == 1) { glin = 0; op_apply(op); return; }
    if (c == 0) return;
#else
    if (k == '"' || k == '\'' || k == '`') {         /* quotes: the nearest one before the cursor on this line (else the next one), and the one after it */
        s = brscan(cur, 0, k, 0, 1);
        if (s == POS_NONE || s < ls) s = brscan(cur, le, k, 0, 0);
        e = s == POS_NONE ? s : brscan((pos_t)(s + 1), le, k, 0, 0);
    } else {                                       /* brackets: the pair around the cursor (may span lines) */
        cc = k == '(' || k == ')' || k == 'b' ? '(' : k == '[' || k == ']' ? '[' : k == '{' || k == '}' || k == 'B' ? '{' : k == '<' || k == '>' ? '<' : 0;
        if (!cc) goto word;
        cl = (u8)(cc + (cc == '(' ? 1 : 2));
        s = cur;
        if (tgetc() == cl && s) s--;
        s = brscan(s, 0, cc, cl, 1);
        e = s == POS_NONE ? s : brscan((pos_t)(s + 1), tlen(), cl, cc, 0);
    }
    if (e == POS_NONE) return;
    if (kind == 'i') { s++; if (tget(s) == '\n' && e > s + 1) s++; } else e++;
    gs = s; ge = e; glin = 0; op_apply(op);
    return;
word:
#endif
    if (k != 'w') return;
    c = cls(tgetc());
    s = skipb(cur, c, 1);
    if (s < ls) s = ls;
    e = skipf(cur, le, c);
    if (kind == 'a' && c) {
        q = skipf(e, le, 0);
        if (q != e) e = q;
        else { s = skipb(s, 0, 1); if (s < ls) s = ls; }
    }
    gs = s; ge = e; glin = 0; op_apply(op);
}
#endif

#ifndef M_ASM
void scroll_view(u16 n, u8 down)
{
    static pos_t e;
    while (n-- && (e = lmove(top, down)) != POS_NONE) top = e;
    shvalid = 0;                                   /* the view moved behind the renderer's back: redraw everything */
    if (lstartc() < top) { cur = top; sethcur(top); }
    else {                                         /* keep the cursor on screen: at most ROWS-1 lines below top */
        pos_t b;
        b = top;
        { u8 i; for (i = 0; i < ROWS - 1 && (e = lmove(b, 1)) != POS_NONE; i++) b = e; }
        if (lstartc() > b) { cur = b; sethcur(b); }
    }
}
#endif

#define LT(x) tget((pos_t)(ls + (x)))
#ifndef M_ASM
void star(u8 fwd) FASTCALL                 /* * #: search for the word under (or after) the cursor */
{
    pos_t ls = lstartc();
    u16 len = (u16)(lendc() - ls), p = (u16)(cur - ls);
    static u8 i;
    while (p < len && cls(LT(p)) != 1) p++;
    if (p >= len) { setmsg("no word"); return; }
    while (p && cls(LT(p - 1)) == 1) p--;
    for (i = 0; i < SRCHSZ && (u16)(p + i) < len && cls(LT(p + i)) == 1; i++) srch[i] = LT(p + i);
    srch[i] = 0;
    slen = i;
    cur = (pos_t)(ls + p);
    sback = (u8)!fwd;
    dosearch(fwd);
}
#endif

#ifndef M_ASM
void screen_line(u8 k) FASTCALL                /* H M L: first / middle / last text line on the screen */
{
    pos_t q = top;
    u16 last = 0, r;
    while (last < ROWS - 1 && (q = lmove(q, 1)) != POS_NONE) last++;
    r = k == 'H' ? 0 : k == 'M' ? (u16)(last / 2) : last;
    sethcur(firstnb(lmoven(top, r, 1)));
}
#endif

#ifndef M_ASM
void begin_ins(u8 k, u16 n)
{
    ikind = k; icnt = n; istart = cur; enter_insert();
}
#endif

#ifndef M_ASM                 /* the Z80 build has normal_key in hal/normal_z80.asm */
static u8 pnm(void) { return (u8)(pend == 'r' || pend == 'g' || pend == 'z' || pend == 'm' || pend == '\'' || pend == '`' || pend == 'q' || pend == '@'); }

static void normal_key(u8 k)
{
    static u16 c2;
#define n nk_n
#define has nk_has
    if (pf) {                                    /* the character after f F t T */
        if (k == 0x1B) { pf = 0; return; }
        lastfc = k;
        lastfk = pf;
        k = pf;
        pf = 0;
    } else if (!pnm()) {
        if ((k == ';' || k == ',') && lastfk) k = k == ';' ? lastfk : (u8)(lastfk ^ 0x20);
        else if ((k | 0x20) == 'f' || (k | 0x20) == 't') { pf = k; return; }
    }
    if (pend != 'r') {
        if (k >= '1' && k <= '9') { count = (u16)(count * 10 + (k - '0')); if (count > 9999) count = 9999; return; }
        if (k == '0' && count > 0) { count = (u16)(count * 10); if (count > 9999) count = 9999; return; }
    }
    if ((pend == 'd' || pend == 'y' || pend == 'c' || pend == 'u' || pend == 'U' || pend == '~') && !pg && !ptob) {
        if (k == 'g') { pg = 1; return; }
        if (k == 'i' || k == 'a' || k == '\'' || k == '`') { ptob = k; return; }
    }
    c2 = count ? count : 1;
    has = (u8)(count != 0);
    count = 0;

    if (pend) {
        u8 p = pend;
        pend = 0;
        n = (u16)(c2 * (pcount ? pcount : 1));
        has = (u8)(has || pcount);
        pcount = 0;
        if (p == 'g') {
            if (k == 'g') { jprev = cur; gotoline(has ? n : 1); }
            else if (k == 'J') cmd_join(n, 0);
            else if (k == 'u' || k == 'U' || k == '~') { pend = k; pcount = has ? n : 0; }
            return;
        }
        if (p == 'z') {                            /* zt zz zb (and z<CR> z. z-): scroll so the cursor line is at the top / middle / bottom */
            top = lmoven(lstartc(), (u16)(k == 't' || k == 0x0D ? 0 : k == 'b' || k == '-' ? ROWS - 1 : ROWS / 2), 0);
            if (top == POS_NONE) top = 0;               /* fewer lines above than that: start at the first line */
            return;
        }
        if (p == 'q' || p == '@') {                /* qa ... q : record into register a (qA appends);  @a  @@ : play it */
            if (mrc || inmac) return;
            if (p == '@' && k == '@') k = mlast;
            if (p == 'q') { if ((k | 0x20) >= 'a' && (k | 0x20) <= 'z') { mrc = k; mlen = 0; } return; }
            if (k < 'a' || k > 'z' || !rlen[k - 'a']) return;
            mlast = k;
            mlen = (u8)(rlen[k - 'a'] > MB ? MB : rlen[k - 'a']);
            tx_aux_get(mb, (u16)(RBASE + roff[k - 'a']), mlen);
            inmac = 1; mc = n; mi = 0;                  /* ed_key feeds the keys once this key is done (no recursion) */
            return;
        }
        if (p == 'Z') {
            if (k == 'Z') { if (modified) dosave(""); if (!modified) quitf = 1; }
            return;
        }
        if (p == 'm' || p == '\'' || p == '`') {
            pos_t q, o = cur;
            if (p != 'm' && (k == '\'' || k == '`')) q = jprev;
            else {
                if (k < 'a' || k > 'z') return;
                q = mk[k - 'a'];
                if (p == 'm') { mk[k - 'a'] = cur; return; }
            }
            if (q == MKNONE) { setmsg("mark not set"); return; }
            jprev = o;
            if (q >= tlen()) q = (pos_t)(tlen() - 1);
            sethcur(p == '`' ? q : firstnb(lstart(q)));
            return;
        }
        if (p == 'r') {
            if (k >= 0x20 && tgetc() != '\n') { tdel(cur, 1); tins(cur, k); }
            return;
        }
        if (ptob) {
            u8 t = ptob;
            ptob = 0; pg = 0;
            if (t == '\'' || t == '`') {          /* d'a  y`a : from the cursor to the mark */
                pos_t a, b, q;
                if (k < 'a' || k > 'z' || (q = mk[k - 'a']) == MKNONE) return;
                a = q < cur ? q : cur; b = q < cur ? cur : q;
                if (t == '\'') { a = lstart(a); b = (pos_t)(lend(b) + 1); }
                gs = a; ge = b; glin = (u8)(t == '\''); op_apply(p);
                return;
            }
            textobj(p, t, k);
            return;
        }
        if (pg) { pg = 0; if (k == 'g') op_motion(p, 0x80, n, has); else if (k == p) op_motion(p, k, n, has); return; }
        op_motion(p, k, n, has);
        return;
    }

    n = c2;
    if (k == 'G' || k == '%' || k == '{' || k == '}' || k == 'n' || k == 'N' || k == '*' || k == '#' || k == ':' || k == '/' || k == '?') jprev = cur;
    switch (k) {
    case 0x1B: return;
    case 'h': case 0x1D: case 0x08:
        { pos_t d = (pos_t)(cur - lstartc()); sethcur((pos_t)(cur - (n > d ? d : n))); } return;
    case 'l': case 0x1C: case ' ':
        { pos_t e = lendc(); pos_t room = (e > cur) ? (pos_t)(e - 1 - cur) : 0; sethcur((pos_t)(cur + (n > room ? room : n))); } return;
    case 'f': case 'F': case 't': case 'T':
        { u16 q = findch(k, lastfc, n); if (q != 0xFFFF) sethcur(k > 'Z' ? (pos_t)(cur + q) : (pos_t)(cur - q)); } return;
    case 'j': case 0x1F: vmove(n, 1); return;
    case 'k': case 0x1E: vmove(n, 0); return;
    case '+': case 0x0D: vmove(n, 1); sethcur(firstnb(lstartc())); return;
    case '-': vmove(n, 0); sethcur(firstnb(lstartc())); return;
    case '|': { pos_t b = lstartc(), room = (lendc() > b) ? (pos_t)(lendc() - 1 - b) : 0; sethcur((pos_t)(b + (n - 1 > room ? room : n - 1))); } return;
    case '0': sethcur(lstartc()); return;
    case '^': sethcur(firstnb(lstartc())); return;
    case '$': { pos_t e, p = lmoven(lstartc(), (u16)(n - 1), 1); if (p == POS_NONE) return; e = lend(p); sethcur(e > p ? (pos_t)(e - 1) : e); want = 0x7FFF; } return;
    case '}': case '{': sethcur(para(n, (u8)(k == '}'))); return;
    case 'w': wordfwd(n); return;
    case 'b': wordback(n); return;
    case 'e': sethcur(endword(cur, n)); return;
    case 'W': bigw = 1; wordfwd(n); bigw = 0; return;
    case 'B': bigw = 1; wordback(n); bigw = 0; return;
    case 'E': bigw = 1; sethcur(endword(cur, n)); bigw = 0; return;
    case 0x04: case 0x15:                                                               /* Ctrl-D / Ctrl-U: half page */
        vmove((u16)(ROWS / 2 * (has ? n : 1)), (u8)(k == 0x04)); sethcur(cur); return;
    case 0x06: case 0x02:                                                               /* Ctrl-F / Ctrl-B: page */
        vmove((pos_t)((ROWS - 2) * n), (u8)(k == 0x06)); sethcur(cur); return;
    case 0x05: case 0x19: scroll_view(n, (u8)(k == 0x05)); return;                      /* Ctrl-E / Ctrl-Y: scroll the view */
    case 'G': gotoline(has ? n : POS_NONE); return;
    case 'x': cmd_x(n); return;
    case 'X': op_motion('d', 'h', n, has); return;
    case 'D': op_motion('d', '$', n, has); return;
    case 'C': op_motion('c', '$', n, has); return;
    case 's': op_motion('c', 'l', n, has); return;
    case 'S': op_motion('c', 'c', n, has); return;
    case 'Y': op_motion('y', 'y', n, has); return;
    case '~': case_toggle(n); return;
    case 'J': cmd_join(n, 1); return;
    case 'p': case 'P': cmd_paste((u8)(k == 'P'), n); return;
    case 'u': case 0x12: cmd_undo((u8)(k == 0x12)); return;          /* Ctrl-R */
    case '.':
        if (lastlen && !replay) { replay = 1; ri = 0; }    /* ed_key feeds lastrec once this key is done */
        return;
    case 'i': begin_ins(k, n); return;
    case 'a': if (tgetc() != '\n') cur++; begin_ins(k, n); return;
    case 'I': cur = firstnb(lstartc()); begin_ins(k, n); return;
    case 'A': cur = lendc(); begin_ins(k, n); return;
    case 'R': begin_ins('i', 1); rmode = 1; return;
    case 'o': { pos_t p = (pos_t)(lendc() + 1); gind(lstartc(), 32); if (tins(p, '\n')) { cur = p; pind(); begin_ins(k, n); } } return;
    case 'O': { pos_t p = lstartc(); gind(p, 32); if (tins(p, '\n')) { cur = p; pind(); begin_ins(k, n); } } return;
    case 'd': case 'y': case 'c': case 'g': case 'z': case '>': case '<': case 'Z': case 'q': case '@': case 'm': case '\'': case '`': pend = k; pcount = has ? n : 0; return;
    case 'r': pend = 'r'; return;
    case 'v': case 'V': case 0x16: vstart = cur; vline = (u8)(k == 'V'); vblk = (u8)(k == 0x16); mode = M_VISUAL; return;
    case 'H': case 'M': case 'L': screen_line(k); return;
    case '%': { pos_t q = matchpos(); if (q != POS_NONE) sethcur(q); } return;
    case '*': case '#': star((u8)(k == '*')); return;
    case 'n': case 'N': dosearch((u8)((k == 'n') != sback)); return;
    case ':': case '/': case '?': mode = M_CMD; cmdch = k; cmdlen = 0; return;
    default: return;
    }
}
#undef n
#undef has
#endif
