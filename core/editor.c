/* editor.c - vim-like editor core (portable C89 subset: host gcc and z88dk sccz80).
 *
 * Invariant: the text is never empty and always ends with '\n' (every line has its own
 * terminator).  So the cursor is always on a real character (possibly the '\n' of an empty line).
 * Text is held in a gap buffer.
 */
#include <string.h>
#include "editor.h"
#include "hal.h"
#include "fs.h"
#include "store.h"
#include "text.h"

#define ROWS   24            /* text rows; row 24 is the status line */
#define COLS   SCR_COLS
#define YSZ    1024                 /* yank register: aux area, offset 0 */
#define CMDSZ  64
#define SRCHSZ 24

#define S_NORMAL 0x04        /* status bar colors (RV added): green / yellow / red */
#define S_INSERT 0x06
#define S_CMD    0x02

/* (not static: the asm twins of the cursor helpers in hal/nav_z80.asm use cur, want and mode) */
pos_t cur;              /* cursor (logical index into text) */
u16 want;             /* wanted column for j/k */
pos_t top; u16 left;        /* first visible line start, first visible column */
u8  mode;
u16 count;
u8  pend;             /* pending operator: 0, 'd', 'y', 'g', 'r' */
u8  modified, quitf;
char fname[16];
char msg[44];
void setmsg(const char *s) { strcpy(msg, s); }
const char m_full[] = "buffer full";
const char m_nofile[] = "no file name", m_nopat[] = "pattern not found", m_werr[] = "write error";
u8  cmdbuf[CMDSZ];
u8  cmdlen, cmdch;
u8  sback;                       /* the last search was ? (n goes backwards) */
u8 ynl;                   /* the yank register holds a line break */
u16 ylen;                 /* bytes in the yank register (<= YSZ) */
u8  srch[SRCHSZ + 1];
u8  slen;
u16 pcount;           /* count typed before an operator */
u8  pg;               /* 'g' typed after an operator */
u8  ptob;             /* 'i' or 'a' typed after an operator (text object) */
#define ISZ 64
#define xb ibuf                     /* scratch for moving data between the text and the aux area (never live together with repeat_insert) */
pos_t istart;             /* count typed before i/a/o/...: repeat the inserted text on Esc */
u16 icnt;
u8 rmode;                      /* R: typed characters overwrite */
u8 ikind;
pos_t vstart;           /* visual mode anchor */
u8  vline;              /* visual mode is linewise (V) */
u8  vblk;               /* visual mode is a block (Ctrl-V) */
u8  bka;                /* block insert: appending (A) */
u16 bkn, bkc;           /* block insert: rows still to fill, column */
void blkrep(void);
u8 ibuf[ISZ + 1];

#define RECSZ 32
u8  rec[RECSZ], lastrec[RECSZ], reclen, recbad;
u8  lastlen, replay, ri;

u16 sh_h1[ROWS + 1], sh_h2[ROWS + 1];   /* per-row checksum of what is on the screen (for diffing; saves 2KB vs a copy) */
u8  sh_sig[ROWS + 1];          /* attribute signature per row: cursor column (0xFF none) / status attribute; 0xFE = unknown */
u8  rowc[COLS], rowa[COLS];
u8  shvalid;
pos_t lc_pos, lc_line = 1;        /* cache: line number (1-based) of the line containing lc_pos */

#ifdef __SCCZ80
#define FASTCALL __z88dk_fastcall
#else
#define FASTCALL
#endif
u16 nk_n; u8 nk_has;         /* normal mode: the count of the command being run, and whether one was typed */
#ifdef M_ASM                 /* cursor helpers in asm (hal/nav_z80.asm); the C versions in ed_undo.c / ed_move.c are the reference */
pos_t lstart(pos_t p) FASTCALL; pos_t lend(pos_t p) FASTCALL; pos_t lstartc(void); pos_t lendc(void); u8 tgetc(void);
void setwant(void); void clampcur(void); void sethcur(pos_t p) FASTCALL; void gotoline(pos_t n) FASTCALL;
pos_t lmove(pos_t p, u8 down); pos_t lmoven(pos_t p, u16 n, u8 down); pos_t para(u16 n, u8 down); void vmove(u16 n, u8 down);
u8 cls(u8 c) FASTCALL; pos_t nextword(pos_t p) FASTCALL; pos_t endword(pos_t p, u16 n); pos_t backword(pos_t p, u16 n);
void wordfwd(u16 n) FASTCALL; void wordback(u16 n) FASTCALL;
pos_t firstnb(pos_t ls) FASTCALL;
void normal_key(u8 k) FASTCALL;      /* hal/normal_z80.asm */
void op_apply(u8 op);                /* hal/op_z80.asm (with get_range / op_motion) */
void vis_range(pos_t *ps, pos_t *pe); void visual_key(u8 k) FASTCALL;   /* hal/visual_z80.asm */
void insert_key(u8 k) FASTCALL; void begin_ins(u8 k, u16 n); void pind(void);   /* hal/insert_z80.asm */
void shift(u8 op) FASTCALL; void cmd_x(u16 n) FASTCALL; void cmd_join(u16 n, u8 sp);   /* hal/edit_z80.asm */
void ulog_add(u8 L, u8 typ, pos_t pos, pos_t len32, const u8 *src, u16 aoff, u8 grp); void touched(pos_t p); u8 mins(pos_t p, const u8 *d, pos_t n);   /* hal/undo_z80.asm */
u8 tins(pos_t p, u8 c); u8 tinsn(pos_t p, const u8 *d, pos_t n); void tdel(pos_t p, pos_t n); void keepinvariant(void); void cmd_undo(u8 redo) FASTCALL;
void cmd_key(u8 k) FASTCALL; void dosearch(u8 forward) FASTCALL; pos_t lineno(pos_t p);   /* hal/ex_z80.asm (lineno is C, in ed_render.c) */
void cmd_paste(u8 before, u16 n); void yankrange(void); void casechg(pos_t s, pos_t e, u8 op); void textobj(u8 op, u8 kind, u8 k); void star(u8 fwd) FASTCALL;
#endif
/* ------------------------------------------------------------ text access */
#define tlen() tx_len()
#define tget(i) tx_get(i)

#include "ed_undo.c"
#include "ed_move.c"
#include "ed_reg.c"
#include "ed_op.c"
#include "ed_file.c"
#include "ed_search.c"
#include "ed_ex.c"
#include "ed_insert.c"
#include "ed_normal.c"
#include "ed_visual.c"
#ifndef M_ASM                 /* the Z80 build has busy / key1 / ed_key in hal/key_z80.asm */
static u8 busy(void) { return (u8)(pend || count || pq || pf); }   /* a command is half typed: operator, count, "x register or f/t target */

static void key1(u8 k)
{
    static u8 idle;
    msg[0] = 0;
    if (mrc && !inmac && !replay) {              /* recording a macro (the keys a . replays are not typed: the . itself is recorded) */
        if (k == 'q' && mode == M_NORMAL && !busy()) {
            reg = mrc; regstore(mb, mlen, 0); reg = 0; mrc = 0;
            return;
        }
        if (mlen < MB) mb[mlen++] = k;
    }
    idle = (u8)(mode == M_NORMAL && !busy() && !reg);
    if (!replay) {
        if (idle) { reclen = 0; recbad = 0; chg = 0; }
        if (reclen < RECSZ) rec[reclen++] = k; else recbad = 1;
    }
    if (idle) {                                  /* a new command: take a new undo group id only if the current one was used, so that
                                                    the 8-bit ids cannot wrap onto a group still in the log (256 plain keys used to) */
        if (ud[0] || (u_n[0] && u_grp[0][u_n[0] - 1] == ugrp)) ugrp++;
        ud[0] = ud[1] = 0;
    }
    if (pq || (k == '"' && !pf && !pend && !vp && (mode == M_NORMAL || mode == M_VISUAL))) {       /* "x : the register for the next command */
        if (pq) { reg = (u8)(((k | 0x20) >= 'a' && (k | 0x20) <= 'z') ? k : 0); }
        pq = (u8)!pq;
        return;
    }
    switch (mode) {
    case M_INSERT: insert_key(k); break;
    case M_CMD:    cmd_key(k); break;
    case M_VISUAL: visual_key(k); break;
    default:       normal_key(k); break;
    }
    if (mode != M_INSERT && mode != M_CMD) clampcur();
    if (!busy() && mode != M_INSERT) reg = 0;
    if (!replay && mode == M_NORMAL && !busy() && chg && !recbad) {
        u8 i;
        for (i = 0; i < reclen; i++) lastrec[i] = rec[i];
        lastlen = reclen;
        chg = 0;
    }
}

/* One key from the keyboard, then whatever it queued: the keys of a dot-repeat (they come first, so that a . inside a macro
   works) and the keys of a macro.  Playback used to call ed_key recursively; a loop keeps the stack flat and the statics safe. */
void ed_key(u8 k)
{
    for (;;) {
        key1(k);
        if (replay) {
            if (ri < lastlen) { k = lastrec[ri++]; continue; }
            replay = 0; chg = 0;
        }
        if (!inmac) break;
        if (mi == mlen) { mi = 0; if (!--mc) { inmac = 0; break; } }
        k = mb[mi++];
    }
    if (uwarn) { setmsg(m_noundo); uwarn = 0; }
}
#endif

#ifndef M_ASM
int ed_quit(void) { return quitf; }
#endif

#include "ed_render.c"
#ifndef M_ASM                 /* (host tests only) */
/* ------------------------------------------------------------ test accessors */
pos_t ed_text(u8 *out, pos_t max)
{
    static pos_t i, n;
    n = tlen();
    if (n > max) n = max;
    for (i = 0; i < n; i++) out[i] = tget(i);
    return n;
}
pos_t ed_cursor(void) { return cur; }
u8  ed_mode(void) { return mode; }
u8  ed_modified(void) { return modified; }
const char *ed_msg(void) { return msg; }
#endif
