/* ed_file.c - part of editor.c (included by it, not compiled on its own): load, save, init */
/* ------------------------------------------------------------ files */
#ifndef M_ASM                 /* the Z80 build has all of this in hal/file_z80.asm (and no ed_set_text) */
void dosave(const char *name)
{
    static int r;
    if (name[0] == 0) name = fname;
    if (name[0] == 0) { setmsg(m_nofile); return; }
    r = fs_save(name, tx_len());
    if (r == 0) {
        modified = 0;
        if (fname[0] == 0) strncpy(fname, name, 15);
        setmsg("written ");
        { u8 w; putnum((u8 *)msg + 8, tx_len(), &w); msg[8 + w] = 0; }
    } else setmsg(m_werr);
}

void ed_goto(u16 n) { gotoline((pos_t)n); }
void ed_redraw(void) { shvalid = 0; }
int ed_load(const char *name)
{
    static pos_t n;
    strncpy(fname, name, 15);
    fname[15] = 0;
    n = fs_load(name, (pos_t)(tx_cap() - 1));
    if (n == FS_TOOBIG) { ed_init(); setmsg("too big (ramdisk 64)"); return 2; }
    if (n == FS_NOFILE) { ed_init(); strncpy(fname, name, 15); setmsg("[New File]"); return 1; }
    if (n == 0 || st_get((pos_t)(n - 1)) != '\n') { u8 nl = '\n'; tx_load_chunk(n, &nl, 1); st_put(n++, '\n'); }
    tx_adopt(n);
    memset(mk, 0xFF, sizeof mk);
    cur = 0; want = 0; top = 0; left = 0;
    modified = 0; mode = M_NORMAL; quitf = 0;
    shvalid = 0;
    lc_pos = 0; lc_line = 1;
    ulog_clear();
    return 0;
}

void ed_init(void)
{
    tx_reset();
    mins(0, (const u8 *)"\n", 1);
    cur = 0; want = 0; top = 0; left = 0;
    mode = M_NORMAL; count = 0; pend = 0;
    modified = 0; quitf = 0;
    fname[0] = 0; msg[0] = 0; lc_pos = 0; lc_line = 1;
    memset(mk, 0xFF, sizeof mk);
    for (reg = 0; reg < 26; reg++) rlen[reg] = 0;
    reg = 0; pq = 0; rtop = 0; mrc = 0; inmac = 0; mlast = 0; ai = 0;
    ulog_clear(); lastlen = 0; pend = 0; pg = 0; ptob = 0; pcount = 0; ylin = 0;
    ylen = 0; slen = 0; cmdlen = 0; icnt = 0;
    shvalid = 0;
}

void ed_set_text(const char *s)
{
    pos_t n;
    n = (pos_t)strlen(s);
    st_write(0, (const u8 *)s, n);
    if (n == 0 || s[n - 1] != '\n') st_put(n++, '\n');
    tx_adopt(n);
    cur = 0; want = 0; top = 0; left = 0;
    modified = 0; lc_pos = 0; lc_line = 1;
    ulog_clear();
}
#endif
