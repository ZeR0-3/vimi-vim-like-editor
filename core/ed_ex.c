/* ed_ex.c - part of editor.c (included by it, not compiled on its own): ex commands (:s :r :g :d :w :q :set :! ...); all of it lives in bank 6 except cmd_key */
#ifndef M_ASM                 /* the Z80 build has all of this in hal/ex_z80.asm */
#pragma codeseg code_far              /* cold code lives in bank 6 (C000h), see tools/bz_build.sh */
/* :s/pat/rep/[g]  and  :%s/pat/rep/[g]  (pat is a regular expression, rep is literal; one undo group) */
static void dosubst(pos_t from, u16 cnt, u8 *a)
{
    static u8 *pat, *rep, *q;
    static u8 rl, g, anch;
    pos_t ls, last;
    static u16 p, m, rl2, r;
    static u8 n, i;
    pat = a;
    for (q = a; *q && *q != '/'; q++) if (*q == '\\' && q[1]) q++;
    if (*q == '/') { *q++ = 0; }
    rep = q;
    while (*q && *q != '/') q++;
    rl = (u8)(q - rep);
    g = 0;
    if (*q == '/') { *q++ = 0; g = (u8)(*q == 'g'); }
    if (pat[0] == 0 && slen) pat = srch;                       /* :s//x/ uses the last pattern */
    if (pat[0] == 0) { setmsg("empty pattern"); return; }
    anch = (u8)(pat[0] == '^');
    if (anch) pat++;
    ls = from;
    last = ls;
    n = 0;
    rxpat = pat; rxanch = anch; rxlit = 0;
    for (;;) {
        p = 0;
        while ((r = rx_scan(ls, p, 0xFFFF, 0)) != RXNONE) {        /* next match start in this line */
            p = r;
            m = mhere(pat, p);
            if (m == p) { p++; continue; }                          /* an empty match does not count */
            m = (u16)(m - p);
            rl2 = 0;                                       /* build the replacement in rowa: & = the matched text, \\& = a literal & */
            tx_read(rowc, (pos_t)(ls + p), m > COLS ? COLS : m);
            for (i = 0; i < rl; i++) {
                if (rep[i] == '&') {
                    if (m > COLS - rl2) { setmsg("rep too long"); goto done; }
                    memcpy(rowa + rl2, rowc, m);
                    rl2 = (u16)(rl2 + m);
                    continue;
                }
                if (rep[i] == '\\' && rep[i + 1] == '&') i++;
                rowa[rl2++] = rep[i];
            }
            tdel((pos_t)(ls + p), m);
            if (rl2 && !tinsn((pos_t)(ls + p), rowa, rl2)) goto done;
            p = (u16)(p + rl2);
            n = 1;
            last = ls;
            if (!g || anch) break;
        }
        if (--cnt == 0) break;
        ls = (pos_t)(lend(ls) + 1);
        if (ls >= tlen()) break;
    }
done:
    if (n == 0) { setmsg(m_nopat); return; }
    sethcur(last);
    setmsg("substituted");
}

static pos_t rat; static u8 rlast;
static int rsink(const u8 *b, u8 n)           /* :r - insert each chunk after the previous one */
{
    if (!tinsn(rat, b, n)) return 0;
    rat = (pos_t)(rat + n); rlast = b[n - 1];
    return 1;
}

static pos_t lineno(pos_t p);
static void dobang(const char *cmd)            /* :!cmd - run it with the OS (E5h); on an OS without that: save, leave a batch file for the V.BAT wrapper to run, quit */
{
    static int r;
    r = fs_exec(cmd, 1);
    if (r != 0xFE) {
        shvalid = 0;
        if (r == 0xF0) setmsg("need 7 free pages: ramdisk 64");
        return;
    }
    if (fname[0] == 0) { setmsg(m_nofile); return; }
    if (modified) dosave("");
    if (modified) return;
    if (fs_bat(cmd, fname, (u16)lineno(cur))) { setmsg(m_werr); return; }
    quitf = 1;
}
static void doread(const char *name)           /* :r file - insert the file below the cursor line */
{
    static pos_t at0;
    static int r;
    if (name[0] == 0) { setmsg(m_nofile); return; }
    rat = at0 = (pos_t)(lendc() + 1); rlast = '\n';
    r = fs_stream(name, rsink);
    if (r == 1) { setmsg("can't open file"); return; }
    if (rlast != '\n') tinsn(rat, (const u8 *)"\n", 1);
    if (rat > at0) { cur = at0; clampcur(); setwant(); }
}

static void runcmd(void);
static u16 rl1, rl2;                      /* the range of an ex command: line numbers */
static u8 na, gsub[32];                   /* addresses given */
static u16 lastln(void) { return (u16)lineno(lstart((pos_t)(tlen() - 1))); }
static void prange(u8 **pp)               /* [N|.|$][,[N|.|$]] or % */
{
    static u8 *q, i;
    static u16 v;
    q = *pp; na = 0;
    rl1 = rl2 = (u16)lineno(cur);
    if (*q == '%') { rl1 = 1; rl2 = lastln(); q++; na = 2; }
    else for (i = 0; i < 2; i++) {
        if (*q >= '0' && *q <= '9') { v = 0; while (*q >= '0' && *q <= '9') v = (u16)(v * 10 + *q++ - '0'); }
        else if (*q == '$') { v = lastln(); q++; }
        else if (*q == '.') { v = rl1; q++; }
        else v = rl1;
        if (i == 0) rl1 = rl2 = v;
        else rl2 = v;
        if (i == 0 && *q != ',') { if (q != *pp) na = 1; break; }
        if (i == 0) q++;
        na = 2;
    }
    if (rl1 > rl2) { v = rl1; rl1 = rl2; rl2 = v; }
    if (rl1 == 0) rl1 = 1;
    *pp = q;
}
static void doglobal(u8 inv, u8 *a)       /* :g/pat/cmd  :v/pat/cmd - the lines are visited from the bottom up */
{
    static u8 *q;
    static u16 k, lo;
    static pos_t ls;
    for (q = a; *q && *q != '/'; q++) if (*q == '\\' && q[1]) q++;
    if (*q == '/') *q++ = 0;
    if (a[0] == 0 || q[0] == 0 || q[0] == 'g' || q[0] == 'v') { setmsg("bad :g"); return; }
    strncpy((char *)srch, (char *)a, SRCHSZ); srch[SRCHSZ] = 0; slen = (u8)strlen((char *)srch);
    strncpy((char *)gsub, (char *)q, 31);
    lo = na ? rl1 : 1;
    for (k = na ? rl2 : lastln(); k >= lo && k; k--) {
        ls = tx_nthline(k);
        rxanch = (u8)(srch[0] == '^'); rxpat = srch + rxanch; rxlit = 0;
        if ((rx_scan(ls, 0, 0xFFFF, 0) != RXNONE) == inv) continue;
        cur = ls;
        strcpy((char *)cmdbuf, (char *)gsub); cmdlen = (u8)strlen((char *)gsub); cmdch = ':';
        runcmd();
        if (quitf) break;
    }
}

static void runcmd(void)
{
    static u8 i;
    char name[16];
    cmdbuf[cmdlen] = 0;
    if (cmdch == ':' && cmdbuf[0] == '!') { dobang((const char *)cmdbuf + 1); return; }
    if (cmdch == ':' && cmdbuf[0] == 'r' && cmdbuf[1] == ' ' && cmdbuf[2] == '!' && cmdlen < CMDSZ - 12) {     /* :r !cmd - the output of cmd, below the cursor line */
        strcpy((char *)cmdbuf + cmdlen, " >VIMI.TMP");
        i = (u8)fs_exec((const char *)cmdbuf + 3, 0);
        shvalid = 0;
        if (i == 0xFE) setmsg("needs LSX with E5h");
        else if (i == 0xF0) setmsg("need 7 free pages: ramdisk 64");
        else { doread("VIMI.TMP"); fs_erase("VIMI.TMP"); }
        return;
    }
    if (cmdch == '/' || cmdch == '?') {
        sback = (u8)(cmdch == '?');
        if (cmdlen) {
            if (cmdlen > SRCHSZ) cmdlen = SRCHSZ;
            for (i = 0; i < cmdlen; i++) srch[i] = cmdbuf[i];
            slen = cmdlen;
            srch[slen] = 0;
        }
        dosearch((u8)!sback);
        return;
    }
#ifdef STKDBG
    if (strcmp((char *)cmdbuf, "stk") == 0) { u16 v = stk_free(); u8 q = 0; char t[6]; do { t[q++] = (char)('0' + v % 10); v /= 10; } while (v); strcpy(msg, "stack free "); for (v = 11; q; ) msg[v++] = t[--q]; msg[v] = 0; return; }
#endif
    if (strncmp((char *)cmdbuf, "set ", 4) == 0) {
        if (strcmp((char *)cmdbuf + 4, "ic") == 0 || strcmp((char *)cmdbuf + 4, "ignorecase") == 0) icase = 1;
        else if (strcmp((char *)cmdbuf + 4, "noic") == 0 || strcmp((char *)cmdbuf + 4, "noignorecase") == 0) icase = 0;
        else if (strcmp((char *)cmdbuf + 4, "ai") == 0 || strcmp((char *)cmdbuf + 4, "autoindent") == 0) ai = 1;
        else if (strcmp((char *)cmdbuf + 4, "noai") == 0 || strcmp((char *)cmdbuf + 4, "noautoindent") == 0) ai = 0;
        else if (strcmp((char *)cmdbuf + 4, "nu") == 0 || strcmp((char *)cmdbuf + 4, "number") == 0) { nu = 1; shvalid = 0; }
        else if (strcmp((char *)cmdbuf + 4, "nonu") == 0 || strcmp((char *)cmdbuf + 4, "nonumber") == 0) { nu = 0; shvalid = 0; }
        else setmsg("unknown option");
        return;
    }
    {
        u8 *p = cmdbuf;
        prange(&p);
        if (na == 9) return;
        if (*p == 0) { if (na) gotoline(rl2); return; }
        if (p[0] == 's' && p[1] == '/') { dosubst(tx_nthline(rl1), (u16)(rl2 - rl1 + 1), p + 2); return; }
        if (p[0] == 'd' && p[1] == 0) {
            gs = tx_nthline(rl1);
            ge = (pos_t)(lend(tx_nthline(rl2)) + 1);
            if (ge > tlen()) ge = tlen();
            glin = 1;
            op_apply('d');
            return;
        }
        if ((p[0] == 'g' || p[0] == 'v') && p[1] == '/') { doglobal((u8)(p[0] == 'v'), p + 2); return; }
        if (na) { setmsg("range not allowed"); return; }
    }
    name[0] = 0;
    i = 0;
    while (i < cmdlen && cmdbuf[i] != ' ') i++;
    if (i < cmdlen) {
        u8 k, j;
        k = i;
        while (k < cmdlen && cmdbuf[k] == ' ') k++;
        for (j = 0; k < cmdlen && j < 15; k++, j++) name[j] = (char)cmdbuf[k];
        name[j] = 0;
        cmdbuf[i] = 0;
    }
    if (strcmp((char *)cmdbuf, "r") == 0) doread(name);
    else if (strcmp((char *)cmdbuf, "w") == 0) dosave(name);
    else if (strcmp((char *)cmdbuf, "wq") == 0 || strcmp((char *)cmdbuf, "x") == 0) {
        dosave(name);
        if (!modified) quitf = 1;
    } else if (strcmp((char *)cmdbuf, "e") == 0 || strcmp((char *)cmdbuf, "e!") == 0) {
        if (cmdbuf[1] == 0 && modified) { setmsg("unsaved (use e!)"); return; }
        if (name[0] == 0) strncpy(name, fname, 15);
        if (name[0] == 0) { setmsg(m_nofile); return; }
        name[15] = 0;
        ed_load(name);
    } else if (strcmp((char *)cmdbuf, "q") == 0) {
        if (modified) setmsg("unsaved (use q!)");
        else quitf = 1;
    } else if (strcmp((char *)cmdbuf, "q!") == 0) quitf = 1;
    else setmsg("unknown command");
}

#pragma codeseg code_compiler
void cmd_key(u8 k) FASTCALL
{
    if (k == 0x1B) { mode = M_NORMAL; return; }
    if (k == 0x0D) { mode = M_NORMAL; runcmd(); return; }
    if (k == 0x08) {
        if (cmdlen == 0) { mode = M_NORMAL; return; }
        cmdlen--;
        return;
    }
    if (k >= 0x20 && cmdlen < CMDSZ - 1) cmdbuf[cmdlen++] = k;
}
#endif
