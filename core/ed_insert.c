/* ed_insert.c - part of editor.c (included by it, not compiled on its own): insert mode */
/* ------------------------------------------------------------ insert mode */
#ifndef M_ASM                 /* the Z80 build has all of this in hal/insert_z80.asm */
static void repeat_insert(void)
{
    static pos_t at;
    static u16 len, r, i;
    if (icnt < 2 || cur <= istart) return;
    len = (u16)(cur - istart);
    if (len > ISZ) { setmsg("too long to repeat"); return; }
    for (i = 0; i < len; i++) ibuf[i] = tget((pos_t)(istart + i));
    if (ikind == 'o' || ikind == 'O') {
        ibuf[len] = '\n';
        at = (pos_t)(lendc() + 1);
        for (r = 1; r < icnt; r++) if (!tinsn(at, ibuf, (u16)(len + 1))) break;
    } else {
        for (r = 1; r < icnt; r++) {
            if (!tinsn(cur, ibuf, len)) break;
            cur = (pos_t)(cur + len);
        }
    }
}

static void leave_insert(void)
{
    rmode = 0;
    if (icnt > 1) repeat_insert();
    if (bkn) blkrep();
    icnt = 0;
    mode = M_NORMAL;
    if (cur > 0 && tget((pos_t)(cur - 1)) != '\n') cur--;
    clampcur();
    setwant();
}

#pragma codeseg code_far
void gind(pos_t src, u8 lim)
{
    ilen = 0;
    if (!ai) return;
    while (ilen < lim && ilen < 32 && (tget((pos_t)(src + ilen)) == ' ' || tget((pos_t)(src + ilen)) == '\t')) { ind[ilen] = tget((pos_t)(src + ilen)); ilen++; }
}
void pind(void)
{
    static u8 i;
    for (i = 0; i < ilen && tins(cur, ind[i]); i++) cur++;
    setwant();
}
#pragma codeseg code_compiler

void insert_key(u8 k) FASTCALL
{
    switch (k) {
    case 0x1B: leave_insert(); return;
    case 0x0D: { pos_t s0 = lstartc(); gind(s0, (u8)(cur - s0 > 32 ? 32 : cur - s0)); if (tins(cur, '\n')) { cur++; want = 0; pind(); } } return;
    case 0x08:
        if (cur > 0) { tdel((pos_t)(cur - 1), 1); cur--; setwant(); }
        return;
    case 0x12:
    case 0x7F:
        if (tgetc() != '\n') tdel(cur, 1);
        return;
    case 0x1C: if (tgetc() != '\n') { cur++; setwant(); } return;
    case 0x1D: if (cur > 0 && tget((pos_t)(cur - 1)) != '\n') { cur--; setwant(); } return;
    case 0x1E: vmove(1, 0); return;
    case 0x1F: vmove(1, 1); return;
    default: break;
    }
    if (k >= 0x20 || k == 0x09) {
        if (rmode && tgetc() != '\n') tdel(cur, 1);
        if (tins(cur, k)) { cur++; setwant(); }
    }
}
#endif
