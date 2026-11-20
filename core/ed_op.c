/* ed_op.c - part of editor.c (included by it, not compiled on its own): operators and motions: ranges, d c y > <, paste, x, undo, join */
static void enter_insert(void) { mode = M_INSERT; }

#define line_start_of(n) tx_nthline(n)

#ifndef M_ASM
static pos_t firstnb(pos_t ls)           /* first non-blank of the line starting at ls */
{
    static pos_t e;
    e = lend(ls);
    while (ls < e && (tget(ls) == ' ' || tget(ls) == '\t')) ls++;
    return ls;
}
#endif

/* motion range for an operator.  op is 'd','y','c'.  Sets [*ps,*pe) and *plin.  Returns 0 if the motion fails. */
u8 pf, lastfk, lastfc;   /* f F t T: pending kind, last find (for ; ,), the character */

#ifndef M_ASM
u16 findch(u8 k, u8 ch, u16 n)         /* distance from the cursor to the target of f/F/t/T (same line), or 0xFFFF */
{
    pos_t ls = lstartc();
    u16 i0 = (u16)(cur - ls), i = i0, len = (u16)(lendc() - ls);
    while (n--) {
        do {
            if (k > 'Z') { if (++i >= len) return 0xFFFF; }
            else { if (i == 0) return 0xFFFF; i--; }
        } while (tget((pos_t)(ls + i)) != ch);
    }
    if (k == 't') i--;
    else if (k == 'T') i++;
    return k > 'Z' ? (u16)(i - i0) : (u16)(i0 - i);
}
#endif

#ifdef U_ASM
pos_t matchb(pos_t cur, pos_t le, pos_t len);
#ifdef U_ASM
int tobj(pos_t cur, pos_t ls, pos_t le, pos_t len, u8 kind, u8 k);
#else
pos_t brscan(pos_t start, pos_t limit, u8 want, u8 other, u8 back);
#endif
#ifndef M_ASM
pos_t matchpos(void) { return matchb(cur, lendc(), tlen()); }
#endif
#else
pos_t brscan(pos_t p, pos_t lim, u8 want, u8 other, u8 back)   /* host version of the asm scanner */
{
    u8 c, d = 0;
    for (;;) {
        if (!back && p >= lim) return POS_NONE;
        c = tget(p);
        if (c == want) { if (!d) return p; d--; }
        else if (c == other) d++;
        if (back) { if (!p) return POS_NONE; p--; } else p++;
    }
}
static pos_t matchpos(void)                   /* % : the bracket matching the first one at/after the cursor on this line */
{
    static const char brk[] = "()[]{}";
    pos_t p = cur, le = lendc(), len = tlen();
    u8 c, k, o, m, d = 0;
    for (;; p++) {
        if (p >= le) return POS_NONE;
        c = tget(p);
        for (k = 0; k < 6 && brk[k] != c; k++) ;
        if (k < 6) break;
    }
    o = c;
    m = (u8)brk[k ^ 1];
    for (;;) {
        c = tget(p);
        if (c == o) d++;
        else if (c == m && --d == 0) return p;
        if (k & 1) { if (p == 0) return POS_NONE; p--; }
        else if (++p >= len) return POS_NONE;
    }
}
#endif

#define s gs
#define e ge
#ifndef M_ASM
void shift(u8 op) FASTCALL     /* > < : one tab in, or one tab / up to 8 spaces out, on every line of [s,e) */
{
    u16 k = (u16)count_nl(s, e);
    static u8 n;
    s = lstart(s);
    e = s;
    while (k--) {
        if (op == '>') {
            if (tget(e) != '\n') tins(e, '\t');
        } else {
            n = 0;
            if (tget(e) == '\t') n = 1;
            else while (n < 8 && tget((pos_t)(e + n)) == ' ') n++;
            if (n) tdel(e, n);
        }
        e = (pos_t)(lend(e) + 1);
    }
    sethcur(firstnb(s));
}
#endif
#undef s
#undef e

#define s gs
#define e ge
#define p gp
#define q gq
#define lin glin
#ifndef M_ASM                 /* the Z80 build has get_range / op_motion in hal/op_z80.asm */
static u8 get_range(u8 op, u8 k, u16 n, u8 has)
{
    static u16 i, d;
    lin = 0;
    s = cur;
    e = cur;
    if (k == 'W' || k == 'B' || k == 'E') {
        u8 r;
        bigw = 1;
        r = get_range(op, (u8)(k + 32), n, has);
        bigw = 0;
        return r;
    }
    switch (k) {
    case 'w':
        if (op == 'c' && cls(tgetc()) != 0) {          /* cw: change to the end of the current word */
            u8 c = cls(tgetc());
            q = cur;
            while ((pos_t)(q + 1) < tlen() && cls(tget((pos_t)(q + 1))) == c) q++;
            if (n > 1) q = endword(q, (pos_t)(n - 1));
            e = (pos_t)(q + 1);
            break;
        }
        p = cur;
        for (i = 0; i < n; i++) {
            q = nextword(p);
            if (i == (u16)(n - 1) && q > lend(p)) q = lend(p);
            p = q;
        }
        e = p;
        break;
    case 'f': case 'F': case 't': case 'T':
        d = findch(k, lastfc, n);
        if (d == 0xFFFF) return 0;
        if (k > 'Z') e = (pos_t)(cur + d + 1); else s = (pos_t)(cur - d);
        break;
    case '%':
        p = matchpos();
        if (p == POS_NONE) return 0;
        if (p >= cur) e = (pos_t)(p + 1); else { s = p; e = (pos_t)(cur + 1); }
        break;
    case '}': e = para(n, 1); break;
    case '{': s = para(n, 0); break;
    case 'e': e = (pos_t)(endword(cur, n) + 1); break;
    case 'b': s = backword(cur, n); e = cur; break;
    case '$':
        p = lmoven(lstartc(), (u16)(n - 1), 1);
        if (p == POS_NONE) return 0;
        e = lend(p);
        break;
    case '0': s = lstartc(); e = cur; break;
    case '^': q = firstnb(lstartc()); if (q < cur) { s = q; e = cur; } else { s = cur; e = q; } break;
    case 'h': case 0x1D: case 0x08: d = (u16)(cur - lstartc()); s = (pos_t)(cur - (n > d ? d : n)); e = cur; break;
    case 'l': case 0x1C: case ' ': d = (u16)(lendc() - cur); e = (pos_t)(cur + (n > d ? d : n)); break;
    case 'j': case 0x1F: case '+': case 0x0D:
        p = lmoven(lstartc(), n, 1);
        if (p == POS_NONE) return 0;
        s = lstartc(); e = (pos_t)(lend(p) + 1); lin = 1;
        break;
    case 'k': case 0x1E: case '-':
        p = lmoven(lstartc(), n, 0);
        if (p == POS_NONE) return 0;
        s = p; e = (pos_t)(lendc() + 1); lin = 1;
        break;
    case 'G': case 0x80:             /* 0x80 = gg */
        p = line_start_of(k == 'G' ? (has ? n : POS_NONE) : (has ? n : 1));
        q = lstartc();
        if (p < q) { s = p; e = (pos_t)(lend(q) + 1); } else { s = q; e = (pos_t)(lend(p) + 1); }
        lin = 1;
        break;
    default:
        if (k == op) {               /* dd yy cc */
            s = lstartc();
            e = s;
            for (i = 0; i < n && e < tlen(); i++) e = (pos_t)(lend(e) + 1);
            lin = 1;
            break;
        }
        return 0;
    }
    return 1;
}

#endif
void casechg(pos_t s, pos_t e, u8 op);
#ifndef M_ASM
void op_apply(u8 op)                    /* the range is in gs/ge, linewise flag in glin */
{
    static pos_t e2;
    if (e <= s) {
        if (op == 'c') { cur = s; enter_insert(); }
        return;
    }
    if (op == 'v') { vstart = s; cur = (pos_t)(e - 1); setwant(); return; }   /* visual-mode text object: select the range */
    if (op == '>' || op == '<') { shift(op); return; }
    if (op == 'u' || op == 'U' || op == '~') { casechg(s, e, op); if (!lin) cur = s; clampcur(); return; }
    yankrange();
    ylin = lin;
    if (reg) regstore(0, ylen, (u8)(ylin | (ynl << 1)));
    if (op == 'y') {
        if (!lin || s < lstartc()) cur = s;
        return;
    }
    if (op == 'd') {
        tdel(s, (pos_t)(e - s));
        keepinvariant();
        if (lin) {
            if (s >= tlen()) s = lstart((pos_t)(tlen() - 1));
            cur = s;
            clampcur();
            cur = lstartc();
            vmove(0, 1);             /* restore wanted column on the new line */
        } else sethcur(s);
        return;
    }
    /* 'c' */
    e2 = lin ? (pos_t)(e - 1) : e;     /* keep the line break of a changed line */
    if (e2 > s) tdel(s, (pos_t)(e2 - s));
    cur = s;
    enter_insert();
}
#endif

#undef s
#undef e
#undef p
#undef q
#undef lin
#ifndef M_ASM
static void op_motion(u8 op, u8 k, u16 n, u8 has)
{
    if (get_range(op, k, n, has)) op_apply(op);
}
#endif

#ifndef M_ASM
static void paste_ins(pos_t pos)                /* insert the yank register at pos (one undo entry) */
{
    static u16 i, m;
    for (i = 0; i < ylen; i += m) {
        m = ylen - i > ISZ ? ISZ : ylen - i;
        tx_aux_get(xb, i, m);
        mins((pos_t)(pos + i), xb, m);
    }
    touched(pos);
    ulog_add(0, T_INS, pos, ylen, 0, 0, ugrp);
}
#endif

#ifndef M_ASM
void cmd_paste(u8 before, u16 n)
{
    static pos_t pos;
    u16 j;
    if (reg && !regload()) return;
    if (ylen == 0) return;
    if (ylin) pos = before ? lstartc() : (pos_t)(lendc() + 1);
    else pos = before ? cur : (tgetc() == '\n' ? cur : (pos_t)(cur + 1));
    if (n > (pos_t)(tx_free() / ylen)) { setmsg(m_full); return; }
    for (j = 0; j < n; j++) paste_ins((pos_t)(pos + (pos_t)(j * ylen)));
    cur = pos;
    if (!ylin && !ynl) cur = (pos_t)(pos + (pos_t)(n * ylen) - 1);
    clampcur();
    setwant();
}
#endif

#ifndef M_ASM
void cmd_x(u16 n) FASTCALL
{
    static pos_t e;
    e = lendc();
    if (cur >= e) return;
    if (n > (pos_t)(e - cur)) n = (pos_t)(e - cur);
    gs = cur; ge = (pos_t)(cur + n); glin = 0; op_apply('d');
}
#endif

#ifndef M_ASM
void cmd_undo(u8 redo) FASTCALL
{
    static u8 from, to, t;
    static u8 g;
    static u16 len, off;
    static pos_t pos, first;
    from = redo ? 1 : 0;
    to = redo ? 0 : 1;
    if (u_n[from] == 0) { setmsg(redo ? "already at newest change" : "already at oldest change"); return; }
    g = u_grp[from][u_n[from] - 1];
    first = cur;
    while (u_n[from] > 0 && u_grp[from][u_n[from] - 1] == g) {
        t = (u8)(u_n[from] - 1);
        pos = u_pos[from][t];
        len = u_len[from][t];
        off = u_off[from][t];
        /* log 'from' holds the op to be reversed; the reverse op is what we apply, and it is queued on the other log
           in the form that re-does the original op */
        ulog_add(to, u_typ[from][t], pos, len, 0, (u16)(UOFF(from) + off), g);
        if ((u_typ[from][t] == T_INS) != (redo != 0)) raw_del(pos, len);   /* undo: INS->delete, DEL->insert; redo: the opposite */
        else raw_ins(pos, (u16)(UOFF(from) + off), len);
        u_n[from] = t;
        u_dn[from] = off;
        first = pos;
    }
    keepinvariant();
    mode = M_NORMAL;
    cur = first;
    clampcur();
    setwant();
}
#endif

#ifndef M_ASM
void cmd_join(u16 n, u8 sp)             /* J (sp=1) and gJ (sp=0): join n lines */
{
    static pos_t e;
    for (n = (u16)(n > 1 ? n - 1 : 1); n; n--) {
        e = lendc();
        if ((pos_t)(e + 1) >= tlen()) return;
        tdel(e, 1);
        if (sp) {
            while (e < tlen() && (tget(e) == ' ' || tget(e) == '\t')) tdel(e, 1);
            if (e > 0 && tget((pos_t)(e - 1)) != '\n' && tget(e) != '\n') tins(e, ' ');
        }
        sethcur(e);
    }
}
#endif

void putnum(u8 *dst, pos_t v, u8 *w);
