/* test_core.c - feed key strings, compare resulting text / cursor / mode.  gcc tests/... */
#include <stdio.h>
#include <string.h>
#include "editor.h"
#include "hal.h"
extern u8 host_ch[SCR_ROWS][SCR_COLS];
extern u8 host_at[SCR_ROWS][SCR_COLS];
extern int host_putrow_calls, host_scroll_calls;

static int fails, total;
static void feed(const char *s) { while (*s) ed_key((u8)*s++); }
static void txt(char *out) { pos_t n = ed_text((u8 *)out, 4000); out[n] = 0; }
#define CHECK_TEXT(name, want) do { char t[4001]; txt(t); total++; \
    if (strcmp(t, want)) { fails++; printf("FAIL %s: got [%s] want [%s]\n", name, t, want); } } while (0)
#define CHECK_INT(name, got, want) do { total++; if ((int)(got) != (int)(want)) { fails++; \
    printf("FAIL %s: got %d want %d\n", name, (int)(got), (int)(want)); } } while (0)

static void fresh(const char *s) { ed_init(); if (s) ed_set_text(s); }

int main(void)
{
    char t[4001];
    int i;

    fresh(0); feed("ihello\x1b");
    CHECK_TEXT("insert", "hello\n"); CHECK_INT("esc cursor", ed_cursor(), 4); CHECK_INT("mode", ed_mode(), M_NORMAL);

    fresh("abc\ndef\n"); feed("jx");
    CHECK_TEXT("j x", "abc\nef\n");
    fresh("abc\ndef\n"); feed("A!\x1b");
    CHECK_TEXT("A", "abc!\ndef\n");
    fresh("abc\ndef\n"); feed("I>\x1b");
    CHECK_TEXT("I", ">abc\ndef\n");
    fresh("abc\ndef\n"); feed("lax\x1b");
    CHECK_TEXT("a", "abxc\ndef\n");
    fresh("abc\ndef\n"); feed("onew\x1b");
    CHECK_TEXT("o", "abc\nnew\ndef\n");
    fresh("abc\ndef\n"); feed("jOnew\x1b");
    CHECK_TEXT("O", "abc\nnew\ndef\n");
    fresh("abc\ndef\n"); feed("Gonew\x1b");
    CHECK_TEXT("o on last", "abc\ndef\nnew\n");

    fresh("one\ntwo\nthree\nfour\n"); feed("dd");
    CHECK_TEXT("dd", "two\nthree\nfour\n");
    fresh("one\ntwo\nthree\nfour\n"); feed("2dd");
    CHECK_TEXT("2dd", "three\nfour\n");
    fresh("one\ntwo\nthree\nfour\n"); feed("d2d");
    CHECK_TEXT("d2d", "three\nfour\n");
    fresh("one\ntwo\nthree\nfour\n"); feed("Gdd");
    CHECK_TEXT("dd last", "one\ntwo\nthree\n"); CHECK_INT("dd last cursor", ed_cursor(), 8);
    fresh("one\ntwo\n"); feed("dddd");
    CHECK_TEXT("dd all", "\n");
    fresh("one\ntwo\nthree\n"); feed("ddp");
    CHECK_TEXT("ddp", "two\none\nthree\n");
    fresh("one\ntwo\nthree\n"); feed("yyjp");
    CHECK_TEXT("yyp", "one\ntwo\none\nthree\n");
    fresh("one\ntwo\nthree\n"); feed("jyyP");
    CHECK_TEXT("yyP", "one\ntwo\ntwo\nthree\n");
    fresh("one\ntwo\nthree\n"); feed("yy2p");
    CHECK_TEXT("2p", "one\none\none\ntwo\nthree\n");
    fresh("one\ntwo\nthree\n"); feed("2yyGp");
    CHECK_TEXT("2yy p", "one\ntwo\nthree\none\ntwo\n");

    fresh("abcdef\n"); feed("3x");
    CHECK_TEXT("3x", "def\n");
    fresh("abcdef\n"); feed("$x");
    CHECK_TEXT("$x", "abcde\n"); CHECK_INT("$x cur", ed_cursor(), 4);
    fresh("abcdef\n"); feed("lllrZ");
    CHECK_TEXT("r", "abcZef\n");
    fresh("abc\n  def\n"); feed("J");
    CHECK_TEXT("J", "abc def\n");

    /* movement */
    fresh("abcdef\nxy\nabcdef\n"); feed("$jj"); CHECK_INT("want col $", ed_cursor(), 15);
    fresh("abcdef\nxy\nabcdef\n"); feed("llllj"); CHECK_INT("col clamp", ed_cursor(), 8);
    fresh("abcdef\nxy\nabcdef\n"); feed("lllljj"); CHECK_INT("col restore", ed_cursor(), 7 + 3 + 4);
    fresh("a b\n"); feed("l"); CHECK_INT("l", ed_cursor(), 1);
    fresh("a b\n"); feed("5l"); CHECK_INT("5l clamp", ed_cursor(), 2);
    fresh("foo bar  baz\n"); feed("w"); CHECK_INT("w", ed_cursor(), 4);
    feed("w"); CHECK_INT("ww", ed_cursor(), 9);
    feed("b"); CHECK_INT("b", ed_cursor(), 4);
    fresh("foo.bar\n"); feed("w"); CHECK_INT("w punct", ed_cursor(), 3);
    fresh("l1\nl2\nl3\nl4\n"); feed("G"); CHECK_INT("G", ed_cursor(), 9);
    feed("gg"); CHECK_INT("gg", ed_cursor(), 0);
    feed("3G"); CHECK_INT("3G", ed_cursor(), 6);
    feed("1G"); CHECK_INT("1G", ed_cursor(), 0);
    feed("2gg"); CHECK_INT("2gg", ed_cursor(), 3);
    feed("k"); CHECK_INT("k", ed_cursor(), 0);
    fresh("l1\nl2\n"); feed("jjjj"); CHECK_INT("j end", ed_cursor(), 3);

    /* insert editing */
    fresh("ab\n"); feed("A\rcd\x1b");
    CHECK_TEXT("enter", "ab\ncd\n");
    fresh("ab\ncd\n"); feed("ji\x08\x1b");
    CHECK_TEXT("bs join", "abcd\n");
    fresh("abc\n"); feed("A\x08\x08x\x1b");
    CHECK_TEXT("bs", "ax\n");
    fresh("abc\n"); feed("i\x12\x1b");
    CHECK_TEXT("del key", "bc\n");

    /* search */
    fresh("foo\nbar\nbaz\nbar\n"); feed("/bar\r"); CHECK_INT("search", ed_cursor(), 4);
    feed("n"); CHECK_INT("n", ed_cursor(), 12);
    feed("n"); CHECK_INT("n wrap", ed_cursor(), 4);
    feed("N"); CHECK_INT("N", ed_cursor(), 12);
    feed("/zzz\r"); CHECK_INT("not found keeps", ed_cursor(), 12);
    fresh("foo1\nbar22\nbaz\nbar333\n"); feed("/r[0-9]*3\r"); CHECK_INT("rx search", ed_cursor(), 17);
    feed("n"); CHECK_INT("rx wrap", ed_cursor(), 17);
    feed("/^ba.\r"); CHECK_INT("rx ^ wrap", ed_cursor(), 5); feed("n"); CHECK_INT("rx ^ n", ed_cursor(), 11); feed("N"); CHECK_INT("rx ^ N", ed_cursor(), 5);
    feed("/[0-9]$\r"); CHECK_INT("rx $", ed_cursor(), 9); feed("N"); CHECK_INT("rx N", ed_cursor(), 3); feed("N"); CHECK_INT("rx N wrap", ed_cursor(), 20);
    fresh("aab ab aab\n"); feed("/ab\r"); CHECK_INT("search first-char false start", ed_cursor(), 1); feed("n"); CHECK_INT("n 2", ed_cursor(), 4); feed("nn"); CHECK_INT("n wrap 2", ed_cursor(), 1); feed("N"); CHECK_INT("N wrap", ed_cursor(), 8);
    fresh("a\nb\nc\nd\n"); feed(":3\r"); CHECK_INT(":3", ed_cursor(), 4);

    /* command line + files */
    remove("t_out.txt");
    fresh(0); feed("ihi\x1b:w t_out.txt\r");
    CHECK_INT("w modified cleared", ed_modified(), 0);
    { FILE *f = fopen("t_out.txt", "rb"); int n = f ? (int)fread(t, 1, 100, f) : -1; if (f) fclose(f);
      total++; if (n != 4 || memcmp(t, "hi\r\n", 4)) { fails++; printf("FAIL file contents n=%d\n", n); } }
    fresh(0); feed("ix\x1b:q\r");
    CHECK_INT("q refuses", ed_quit(), 0);
    feed(":q!\r"); CHECK_INT("q!", ed_quit(), 1);
    fresh(0); feed("ix\x1b:wq t_out2.txt\r"); CHECK_INT("wq", ed_quit(), 1);
    fresh(0); feed(":q\r"); CHECK_INT("q clean", ed_quit(), 1);
    fresh(0); feed(":zzz\r"); CHECK_INT("unknown cmd msg", strlen(ed_msg()) > 0, 1);
    ed_init(); CHECK_INT("load new", ed_load("nonexistent.txt"), 1);
    { FILE *f = fopen("t_in.txt", "wb"); fputs("line1\r\nline2\r\n\x1a", f); fclose(f); }
    ed_init(); CHECK_INT("load", ed_load("t_in.txt"), 0); CHECK_TEXT("load text", "line1\nline2\n");
    feed("dd:w\r");
    { FILE *f = fopen("t_in.txt", "rb"); int n = (int)fread(t, 1, 100, f); fclose(f);
      total++; if (n != 7 || memcmp(t, "line2\r\n", 7)) { fails++; printf("FAIL resave n=%d\n", n); } }

    /* render: only changed rows are sent */
    fresh("abc\ndef\nghi\n"); ed_render();
    CHECK_INT("first render rows", host_putrow_calls, 25);
    host_putrow_calls = 0; ed_render(); CHECK_INT("idle render", host_putrow_calls, 0);
    feed("l"); host_putrow_calls = 0; ed_render(); CHECK_INT("move in line", host_putrow_calls, 2); /* text row + status col */
    feed("j"); host_putrow_calls = 0; ed_render(); CHECK_INT("move line", host_putrow_calls, 3);
    CHECK_INT("cursor attr", host_at[1][1], AT_WHITE | AT_RV);
    CHECK_INT("cursor char", host_ch[1][1], 'e');
    CHECK_INT("tilde", host_ch[5][0], '~');
    CHECK_INT("status mode", host_ch[24][0], 'N');
    feed("i"); ed_render(); CHECK_INT("status insert", host_ch[24][3], 'I');

    /* scroll: 100 lines */
    { char big[2000]; int n = 0; for (i = 1; i <= 100; i++) n += sprintf(big + n, "L%d\n", i); fresh(big); }
    ed_render(); CHECK_INT("row0 L1", host_ch[0][1], '1');
    feed("G"); ed_render();
    CHECK_INT("G bottom row", host_ch[23][0], 'L'); CHECK_INT("G bottom 0", host_ch[23][2], '0');
    CHECK_INT("G cursor attr", host_at[23][0], AT_WHITE | AT_RV);
    CHECK_INT("G top row L77", host_ch[0][1] == '7' && host_ch[0][2] == '7', 1);
    feed("gg"); ed_render(); CHECK_INT("gg top", host_ch[0][1], '1'); CHECK_INT("gg cursor attr", host_at[0][0], AT_WHITE | AT_RV);
    /* long line horizontal scroll */
    { char b[300]; memset(b, 'x', 199); b[199] = '\n'; b[200] = 0; fresh(b); feed("$"); ed_render();
      CHECK_INT("hscroll cursor", host_at[0][79], AT_WHITE | AT_RV); }

    /* hardware scroll: one-line scrolls redraw only a few rows, and the visible screen stays correct */
    { char big[2000]; int n = 0, k2, r;
      for (i = 1; i <= 100; i++) n += sprintf(big + n, "L%d\n", i);
      fresh(big); ed_render();
      feed("22j"); ed_render();                      /* cursor on row 22 (line 23): no scroll yet */
      feed("jj"); host_putrow_calls = 0; host_scroll_calls = 0; ed_render();   /* line 25 -> scrolls by 1 */
      CHECK_INT("scroll calls", host_scroll_calls, 1);
      CHECK_INT("scroll rows redrawn", host_putrow_calls <= 4, 1);
      for (r = 0; r < 24; r++) { char want[8]; sprintf(want, "L%d", r + 2); total++;
          if (memcmp(host_ch[r], want, strlen(want))) { fails++; printf("FAIL scroll row %d: [%.4s]\n", r, (char *)host_ch[r]); } }
      CHECK_INT("status after scroll", host_ch[24][0], 'N');
      CHECK_INT("cursor after scroll", host_at[23][0], AT_WHITE | AT_RV);
      for (k2 = 0; k2 < 30; k2++) { feed("j"); ed_render(); }   /* many one-line scrolls (wraps VRAM) */
      for (r = 0; r < 24; r++) { char want[8]; sprintf(want, "L%d", r + 32); total++;
          if (memcmp(host_ch[r], want, strlen(want))) { fails++; printf("FAIL scroll2 row %d: [%.4s]\n", r, (char *)host_ch[r]); } }
      for (k2 = 0; k2 < 45; k2++) { feed("k"); ed_render(); }   /* scroll back up */
      for (r = 0; r < 24; r++) { char want[8]; sprintf(want, "L%d", r + 10); total++;
          if (memcmp(host_ch[r], want, strlen(want))) { fails++; printf("FAIL scrollup row %d: [%.4s]\n", r, (char *)host_ch[r]); } }
      CHECK_INT("status after up", host_ch[24][0], 'N');
      feed("G"); ed_render(); CHECK_INT("big jump bottom", host_ch[23][1], '1'); CHECK_INT("big jump status", host_ch[24][0], 'N');
    }


    /* operators + motions */
    fresh("foo bar baz\n"); feed("dw");      CHECK_TEXT("dw", "bar baz\n");
    fresh("foo bar baz\n"); feed("d2w");     CHECK_TEXT("d2w", "baz\n");
    fresh("foo bar baz\n"); feed("2dw");     CHECK_TEXT("2dw", "baz\n");
    fresh("foo bar\n"); feed("wdw");         CHECK_TEXT("dw last", "foo \n");
    fresh("foo bar\n"); feed("cwxy\x1b");    CHECK_TEXT("cw", "xy bar\n");
    fresh("foo bar\n"); feed("de");          CHECK_TEXT("de", " bar\n");
    fresh("foo bar\n"); feed("wdb");         CHECK_TEXT("db", "bar\n");
    fresh("foo bar\n"); feed("wd$");         CHECK_TEXT("d$", "foo \n"); CHECK_INT("d$ cur", ed_cursor(), 3);
    fresh("foo bar\n"); feed("wD");          CHECK_TEXT("D", "foo \n");
    fresh("foo bar\n"); feed("wd0");         CHECK_TEXT("d0", "bar\n");
    fresh("abc\n"); feed("ldh");             CHECK_TEXT("dh", "bc\n");
    fresh("abc\n"); feed("dl");              CHECK_TEXT("dl", "bc\n");
    fresh("a\nb\nc\n"); feed("dj");          CHECK_TEXT("dj", "c\n");
    fresh("a\nb\nc\n"); feed("jdk");         CHECK_TEXT("dk", "c\n");
    fresh("a\nb\nc\n"); feed("Gdj");         CHECK_TEXT("dj fails at end", "a\nb\nc\n");
    fresh("a\nb\nc\n"); feed("jdG");         CHECK_TEXT("dG", "a\n");
    fresh("a\nb\nc\n"); feed("jdgg");        CHECK_TEXT("dgg", "c\n");
    fresh("abc\ndef\n"); feed("ccX\x1b");    CHECK_TEXT("cc", "X\ndef\n");
    fresh("foo bar\n"); feed("ywP");         CHECK_TEXT("yw P", "foo foo bar\n");
    fresh("foo bar\n"); feed("yw$p");        CHECK_TEXT("yw $p", "foo barfoo \n");
    fresh("ab\n"); feed("xp");               CHECK_TEXT("xp", "ba\n");
    fresh("abc\n"); feed("$X");              CHECK_TEXT("X", "ac\n");
    fresh("abc\n"); feed("sX\x1b");          CHECK_TEXT("s", "Xbc\n");
    fresh("abc\ndef\n"); feed("SX\x1b");     CHECK_TEXT("S", "X\ndef\n");
    /* undo log overflow of one group: all or nothing */
    fresh("a\na\na\na\na\n"); feed(":%s/a/b/\r"); feed("u"); CHECK_TEXT("undo :%s small", "a\na\na\na\na\n");
    { char big[200]; int i, o = 0; for (i = 0; i < 40; i++) o += sprintf(big + o, "a\n");
      fresh(big); feed(":%s/a/b/\r"); feed("u");
      txt(big); total++; if (strchr(big, 'a') != NULL) { fails++; printf("FAIL undo of a too big group must not be partial\n"); } }
    /* H M L ZZ */
    { char big[400]; int i, o = 0; for (i = 1; i <= 80; i++) o += sprintf(big + o, "l%d\n", i);
      fresh(big); feed("L"); CHECK_INT("L at least below top", ed_cursor() > 0, 1);
      feed("H"); CHECK_INT("H back to top", ed_cursor(), 0);
      feed("M"); CHECK_INT("M between", ed_cursor() > 0, 1);
    }
    fresh("a\nb\n"); feed("ZZ"); CHECK_INT("ZZ quits", ed_quit(), 1);
    /* % and > < */
    fresh("f(a[1], {b})\n"); feed("%");          CHECK_INT("% fwd", ed_cursor(), 11);
    fresh("f(a[1], {b})\n"); feed("%%");         CHECK_INT("% back", ed_cursor(), 1);
    fresh("f(a[1], {b})\n"); feed("fa%");        CHECK_INT("% on [ from a? finds [ after", ed_cursor(), 5);
    fresh("f(a[1], {b})\n"); feed("$%");         CHECK_INT("% on )", ed_cursor(), 1);
    fresh("(a\nb)\nc\n"); feed("%");             CHECK_INT("% multi-line", ed_cursor(), 4);
    fresh("(a\nb\n"); feed("%");                 CHECK_INT("% unmatched", ed_cursor(), 0);
    fresh("abc\n"); feed("%");                   CHECK_INT("% none", ed_cursor(), 0);
    fresh("f(a(b)c)d\n"); feed("d%");            CHECK_TEXT("d%", "d\n");
    fresh("f(a(b)c)d\n"); feed("fcd%");          CHECK_TEXT("d% from c finds ) after", "f)d\n");
    fresh("f(a(b)c)d\n"); feed("f)d%");          CHECK_TEXT("d% back", "f(ac)d\n");
    fresh("a\nb\nc\n"); feed(">>");             CHECK_TEXT(">>", "\ta\nb\nc\n");
    fresh("a\nb\nc\n"); feed("2>>");            CHECK_TEXT("2>>", "\ta\n\tb\nc\n");
    fresh("a\nb\nc\n"); feed(">j");             CHECK_TEXT(">j", "\ta\n\tb\nc\n");
    fresh("\n\n"); feed(">>");                   CHECK_TEXT(">> empty line", "\n\n");
    fresh("\ta\n  b\n"); feed("<<");            CHECK_TEXT("<< tab", "a\n  b\n");
    fresh("\ta\n    b\n"); feed("j<<");        CHECK_TEXT("<< spaces", "\ta\nb\n");
    fresh("a\nb\nc\n"); feed("Vj>");            CHECK_TEXT("V>", "\ta\n\tb\nc\n");
    fresh("a\nb\n"); feed(">>u");                CHECK_TEXT(">> undo", "a\nb\n");
    /* * # */
    fresh("foo bar\nbaz foo x\nfoo.\n"); feed("*");  CHECK_INT("*", ed_cursor(), 12);
    fresh("foo bar\nbaz foo x\nfoo.\n"); feed("**"); CHECK_INT("**", ed_cursor(), 18);
    fresh("foo bar\nbaz foo x\nfoo.\n"); feed("***"); CHECK_INT("*** wraps", ed_cursor(), 0);
    fresh("foo bar\nbaz foo x\nfoo.\n"); feed("#");  CHECK_INT("# wraps back", ed_cursor(), 18);
    fresh("foo bar\nbaz foo x\nfoo.\n"); feed("lll*"); CHECK_INT("* on blank goes to next word", ed_cursor(), 4);
    fresh("  \nfoo\n"); feed("*");          CHECK_INT("* none on line", ed_cursor(), 0);
    /* f F t T ; , */
    fresh("a,b,c,d\n"); feed("f,");         CHECK_INT("f,", ed_cursor(), 1);
    fresh("a,b,c,d\n"); feed("2f,");        CHECK_INT("2f,", ed_cursor(), 3);
    fresh("a,b,c,d\n"); feed("f,;");        CHECK_INT("f,;", ed_cursor(), 3);
    fresh("a,b,c,d\n"); feed("$F,");        CHECK_INT("F,", ed_cursor(), 5);
    fresh("a,b,c,d\n"); feed("$F,;");       CHECK_INT("F,;", ed_cursor(), 3);
    fresh("a,b,c,d\n"); feed("f,;,");       CHECK_INT("f,;,", ed_cursor(), 1);
    fresh("a,b,c,d\n"); feed("tc");         CHECK_INT("tc", ed_cursor(), 3);
    fresh("a,b,c,d\n"); feed("$Tb");        CHECK_INT("Tb", ed_cursor(), 3);
    fresh("a,b,c,d\n"); feed("fz");         CHECK_INT("fz none", ed_cursor(), 0);
    fresh("a,b,c,d\n"); feed("df,");        CHECK_TEXT("df,", "b,c,d\n");
    fresh("a,b,c,d\n"); feed("dt,");        CHECK_TEXT("dt,", ",b,c,d\n");
    fresh("a,b,c,d\n"); feed("$dF,");       CHECK_TEXT("dF,", "a,b,cd\n");
    fresh("a,b,c,d\n"); feed("ct,X\x1b");   CHECK_TEXT("ct,", "X,b,c,d\n");
    fresh("a,b,c,d\n"); feed("rxl;");       CHECK_TEXT("r then ;", "x,b,c,d\n");
    fresh("a,b,c,d\n"); feed("d2f,");       CHECK_TEXT("d2f,", "c,d\n");
    fresh("abC\n"); feed("3~");              CHECK_TEXT("~", "ABc\n");
    fresh("foo bar baz\n"); feed("wdiw");    CHECK_TEXT("diw", "foo  baz\n");
    fresh("foo bar baz\n"); feed("wdaw");    CHECK_TEXT("daw", "foo baz\n");
    fresh("foo bar baz\n"); feed("wciwX\x1b"); CHECK_TEXT("ciw", "foo X baz\n");
    fresh("  foo\n"); feed("^"); CHECK_INT("^", ed_cursor(), 2);
    fresh("foo bar\n"); feed("e"); CHECK_INT("e", ed_cursor(), 2);


    /* a change too big for the undo log: says so (and stays all-or-nothing) */
    { static char big[1400]; int q; big[0] = 0; for (q = 0; q < 40; q++) strcat(big, "line of twenty chars\n"); strcat(big, "end\n");
      fresh(big); feed("30dd"); CHECK_INT("big delete warns", strcmp(ed_msg(), "too big: cannot undo"), 0);
      feed("u"); CHECK_INT("big delete: nothing to undo", strcmp(ed_msg(), "already at oldest change"), 0);
      fresh(big); feed("2dd"); CHECK_INT("small delete: no warning", ed_msg()[0], 0); }
    /* group ids are 8 bit: 256 keys after a dropped group, a new change must still be logged (was: lost + undo damaged the text) */
    { static char big[1400]; int q; big[0] = 0; for (q = 0; q < 40; q++) strcat(big, "line of twenty chars\n"); strcat(big, "ab\ncd\n");
      fresh(big); feed("30ddGk"); for (q = 0; q < 252; q++) feed("l"); feed("xdd"); feed("u");
      txt(t); total++; if (strcmp(t + strlen(t) - 5, "a\ncd\n")) { fails++; printf("FAIL undo after group id wrap: tail [%s]\n", t + strlen(t) - 9); } }
    /* ... and two changes 256 keys apart are still separate undo steps */
    fresh("abc\ndef\n"); feed("xj"); for (i = 0; i < 253; i++) feed("l"); feed("0x"); feed("u");
    CHECK_TEXT("undo steps stay separate after 256 keys", "bc\ndef\n");
    fresh("abc\n"); feed("x"); feed("u"); feed("\x12"); feed("x"); feed("u"); CHECK_TEXT("undo redo then new change", "bc\n");
    fresh("abc\n"); feed("ix\x1b" "iy\x1b" "u"); CHECK_TEXT("two insert sessions are two undo steps", "xabc\n");
    /* half-typed commands: "a then f-target, count then operator: the register / dot-repeat state must survive until the command is complete */
    fresh("abc abc\n"); feed("\"ayyfcx"); CHECK_TEXT("f target after register prefix", "ab abc\n");
    fresh("a b c d e\n"); feed("dtc."); CHECK_TEXT("dt then dot", "c d e\n");
    fresh("one\ntwo\nthree\nfour\n"); feed("2dd."); CHECK_TEXT("2dd then dot", "\n");
    fresh("a1 b2 c3\n"); feed("fb;x"); CHECK_TEXT("f then ; then x", "a1 2 c3\n");
    /* playback is a queue, not recursion: dot inside a macro, counts, and the keys after the playback still run in order */
    fresh("abcdef\nabcdef\nabcdef\n"); feed("qax.jq"); feed("2@a"); CHECK_TEXT("dot inside a macro, played twice", "cdef\ncdef\ncdef\n");
    fresh("a\nb\nc\nd\n"); feed("qaddq@aix\x1b"); CHECK_TEXT("keys after a macro", "xc\nd\n");
    fresh("abcdef\n"); feed("x.ix\x1b"); CHECK_TEXT("keys after a dot", "xcdef\n");
    fresh("abcdefgh\n"); feed("qaxq@a."); CHECK_TEXT("dot after a macro repeats its last change", "defgh\n");
    /* Ctrl-V: the highlight shows the block being selected (it used to show the columns of the previous block command) */
    { fresh("abcdef\nabcdef\nabcdef\n"); feed("l\x16jl"); ed_render();
      CHECK_INT("block highlight: left of the block", host_at[0][0] & 0x40, 0);
      CHECK_INT("block highlight: first column, row 1", host_at[0][1] & 0x40, 0x40);
      CHECK_INT("block highlight: last column, row 1", host_at[0][2] & 0x40, 0x40);
      CHECK_INT("block highlight: first column, row 2", host_at[1][1] & 0x40, 0x40);
      CHECK_INT("block highlight: right of the block", host_at[1][3] & 0x40, 0);
      CHECK_INT("block highlight: row below", host_at[2][1] & 0x40, 0);
      feed("\x1b"); }
    /* undo / redo */
    fresh("abc\n"); feed("xu");              CHECK_TEXT("xu", "abc\n");
    fresh("abc\n"); feed("xxu");             CHECK_TEXT("xxu", "bc\n");
    fresh("abc\n"); feed("xxuu");            CHECK_TEXT("xxuu", "abc\n");
    fresh("abc\n"); feed("xxuu\x12");        CHECK_TEXT("redo 1", "bc\n");
    feed("\x12");                            CHECK_TEXT("redo 2", "c\n");
    fresh(0); feed("ihello\x1bu");           CHECK_TEXT("undo insert session", "\n");
    fresh("abc\n"); feed("Aend\x1bu");       CHECK_TEXT("undo A", "abc\n");
    fresh("a\nb\nc\n"); feed("ddu");         CHECK_TEXT("undo dd", "a\nb\nc\n");
    fresh("a\nb\nc\n"); feed("jddu");        CHECK_INT("undo dd cursor", ed_cursor(), 2);
    fresh("abc\n"); feed("onew\x1bu");       CHECK_TEXT("undo o", "abc\n");
    fresh("a\nb\n"); feed("yyjpu");          CHECK_TEXT("undo p", "a\nb\n");
    fresh("foo bar\n"); feed("cwxy\x1bu");   CHECK_TEXT("undo cw", "foo bar\n");
    fresh("abc\n"); feed("xuxx\x12");        CHECK_TEXT("new edit kills redo", "c\n"); CHECK_INT("redo msg", strlen(ed_msg()) > 0, 1);
    fresh("abc\n"); feed("u");               CHECK_TEXT("undo nothing", "abc\n"); CHECK_INT("undo msg", strlen(ed_msg()) > 0, 1);
    fresh("a b c\n"); feed("dwdwdwuuu");     CHECK_TEXT("undo x3", "a b c\n");
    fresh("one\ntwo\nthree\n"); feed("dddd"); feed("uu"); CHECK_TEXT("undo dd dd", "one\ntwo\nthree\n");

    /* dot repeat */
    fresh("abc def\n"); feed("x.");          CHECK_TEXT("dot x", "c def\n");
    fresh("1\n2\n3\n4\n"); feed("dd.");      CHECK_TEXT("dot dd", "3\n4\n");
    fresh("a b c\n"); feed("cwX\x1bw.");     CHECK_TEXT("dot cw", "X X c\n");
    fresh("ab\nc\n"); feed("A!\x1bj.");      CHECK_TEXT("dot A", "ab!\nc!\n");
    fresh("abcdef\n"); feed("2x.");          CHECK_TEXT("dot 2x", "ef\n");
    fresh("a\n"); feed("ox\x1b.");           CHECK_TEXT("dot o", "a\nx\nx\n");
    fresh("abc\n"); feed("x.u");             CHECK_TEXT("undo dot", "bc\n");
    fresh("abc\n"); feed("xl.");             CHECK_TEXT("dot after move", "b\n");
    fresh("a b c d\n"); feed("dw..");        CHECK_TEXT("dot dot", "d\n");


    /* WORD motions */
    fresh("foo.bar baz\n"); feed("W");        CHECK_INT("W", ed_cursor(), 8);
    fresh("foo.bar baz\n"); feed("$B");       CHECK_INT("B", ed_cursor(), 8);
    fresh("foo.bar baz\n"); feed("E");        CHECK_INT("E", ed_cursor(), 6);
    fresh("foo.bar baz\n"); feed("dW");       CHECK_TEXT("dW", "baz\n");
    fresh("foo.bar baz\n"); feed("cWx\x1b"); CHECK_TEXT("cW", "x baz\n");
    fresh("a.b c.d\n");   feed("wD");          CHECK_TEXT("w then D", "a\n");
    /* counts for insert commands */
    fresh("x\n"); feed("3ihi\x1b");         CHECK_TEXT("3ihi", "hihihix\n");
    fresh("x\n"); feed("2Aab\x1b");         CHECK_TEXT("2A", "xabab\n");
    fresh("x\n"); feed("3oq\x1b");          CHECK_TEXT("3o", "x\nq\nq\nq\n");
    fresh("x\n"); feed("2Oq\x1b");          CHECK_TEXT("2O", "q\nq\nx\n");
    fresh("ab\n"); feed("3ax\x1b");         CHECK_TEXT("3a", "axxxb\n");
    fresh("x\n"); feed("2ihi\x1bj.");       CHECK_TEXT("count then dot", "hihhihiix\n");
    fresh("x\n"); feed("ihi\x1b");          CHECK_TEXT("no count", "hix\n");

    /* file load: per-block newline hints (multi-block file) */
    { FILE *f = fopen("/tmp/t_big_e.txt", "wb"); int L; long off = 0, want1500 = 0, want2400 = 0; char b[32];
      for (L = 1; L <= 2400; L++) { int m = sprintf(b, "line %d\r\n", L); fputs(b, f); if (L == 1499) want1500 = off + (m - 1); if (L == 2399) want2400 = off + (m - 1); off += m - 1; }
      fclose(f);
      ed_init(); ed_load("/tmp/t_big_e.txt");
      feed(":1500\r"); CHECK_INT("hint :1500", ed_cursor(), want1500);
      feed(":2400\r"); CHECK_INT("hint :2400", ed_cursor(), want2400);
      feed("gg"); CHECK_INT("hint gg", ed_cursor(), 0);
      feed("G"); ed_render(); CHECK_INT("hint G", ed_cursor() >= want2400, 1);
      feed("700Gdd"); feed(":701\r"); CHECK_INT("hint after edit", ed_cursor() > 0, 1);
    }
    /* :e */
    { FILE *f = fopen("/tmp/t_e1.txt", "wb"); fputs("alpha\r\nbeta\r\n", f); fclose(f); }
    fresh("old\n"); feed(":e /tmp/t_e1.txt\r");         CHECK_TEXT(":e", "alpha\nbeta\n");
    fresh("old\n"); feed("x:e /tmp/t_e1.txt\r");        CHECK_TEXT(":e refused when modified", "ld\n");
    fresh("old\n"); feed("x:e! /tmp/t_e1.txt\r");       CHECK_TEXT(":e!", "alpha\nbeta\n");
    fresh("old\n"); feed(":e /tmp/t_e1.txt\rjx");      CHECK_TEXT(":e then edit", "alpha\neta\n");
    feed(":e! \r");                                     CHECK_TEXT(":e! reload", "alpha\nbeta\n");
    fresh("old\n"); feed(":e /tmp/t_none_zz.txt\r");   CHECK_TEXT(":e new file", "\n");
    /* :s */
    fresh("foo foo\nfoo\n"); feed(":s/foo/bar/\r");     CHECK_TEXT(":s first", "bar foo\nfoo\n");
    fresh("foo foo\nfoo\n"); feed(":s/foo/bar/g\r");    CHECK_TEXT(":s g", "bar bar\nfoo\n");
    fresh("foo foo\nfoo\n"); feed(":%s/foo/x/g\r");     CHECK_TEXT(":%s g", "x x\nx\n");
    fresh("a.b\n"); feed(":s/\\./,,/\r");                 CHECK_TEXT(":s literal", "a,,b\n");
    fresh("abab\n"); feed(":s/ab//g\r");                CHECK_TEXT(":s delete", "\n");
    fresh("foo foo\nfoo\n"); feed(":%s/foo/bar/g\ru"); CHECK_TEXT(":s undo", "foo foo\nfoo\n");
    fresh("abc\n"); feed(":s/zz/y/\r");                 CHECK_TEXT(":s none", "abc\n");
    fresh("aaa\n"); feed(":s/a/aa/g\r");                CHECK_TEXT(":s grow", "aaaaaa\n");
    fresh("a\nb\nfoo\n"); feed(":s/foo/q/\r");          CHECK_TEXT(":s cur line only", "a\nb\nfoo\n");
    /* :s regular expressions */
    fresh("abc\n"); feed(":s/a.c/X/\r");                CHECK_TEXT(":s .", "X\n");
    fresh("abbc\n"); feed(":s/b*/X/\r");                CHECK_TEXT(":s star skips empty", "aXc\n");
    fresh("abab\n"); feed(":s/^a/X/g\r");               CHECK_TEXT(":s ^", "Xbab\n");
    fresh("abab\n"); feed(":s/b$/X/\r");                CHECK_TEXT(":s $", "abaX\n");
    fresh("a12b3\n"); feed(":s/[0-9]*/N/g\r");          CHECK_TEXT(":s class star g", "aNbN\n");
    fresh("a1b2\n"); feed(":s/[^a-c]/_/g\r");           CHECK_TEXT(":s negated class", "a_b_\n");
    fresh("a.b axb\n"); feed(":s/a\\.b/X/g\r");         CHECK_TEXT(":s escaped dot", "X axb\n");
    fresh("hello world\n"); feed(":s/.*/X/\r");          CHECK_TEXT(":s .*", "X\n");
    fresh("ab  \ncd \nef\n"); feed(":%s/ *$//\r");     CHECK_TEXT(":%s trailing spaces", "ab\ncd\nef\n");
    fresh("foo bar\n"); feed(":s/o*b/X/\r");            CHECK_TEXT(":s o*b", "foo Xar\n");
    fresh("x]y\n"); feed(":s/[]]/Z/\r");                CHECK_TEXT(":s ] in class", "xZy\n");
    fresh("a-b\n"); feed(":s/[a-]/Z/g\r");              CHECK_TEXT(":s - at end", "ZZb\n");
    fresh("aXb\n"); feed(":s/X/\\/\r");               CHECK_TEXT(":s backslash rep literal", "a\\b\n");
    fresh("a/b\n"); feed(":s/a\\/b/X/\r");             CHECK_TEXT(":s escaped slash", "X\n");
    /* :s with & */
    fresh("abc\n"); feed(":s/b/[&]/\r");               CHECK_TEXT(":s &", "a[b]c\n");
    fresh("abab\n"); feed(":s/ab/&&/g\r");             CHECK_TEXT(":s && g", "ababab" "ab\n");
    fresh("a.b\n"); feed(":s/\\./\\&/\r");              CHECK_TEXT(":s escaped &", "a&b\n");
    fresh("foo bar\n"); feed(":s/[a-z]*/<&>/g\r");     CHECK_TEXT(":s class & g", "<foo> <bar>\n");
    fresh("hello\n"); feed(":s/.*/\"&\"/\ru");         CHECK_TEXT(":s & undo", "hello\n");
    fresh("ab\n"); feed(":s/b/x\\y/\r");             CHECK_TEXT(":s lone backslash", "ax\\y\n");
    /* visual mode */
    fresh("one two three\n"); feed("wved");      CHECK_TEXT("v e d", "one  three\n");
    fresh("abcdef\n"); feed("lvlyp");            CHECK_TEXT("v y p", "abbccdef\n");
    fresh("a\nb\nc\n"); feed("jVd");             CHECK_TEXT("V d", "a\nc\n");
    fresh("a\nb\nc\n"); feed("Vjd");             CHECK_TEXT("Vj d", "c\n");
    fresh("abcdef\n"); feed("lvlcX\x1b");        CHECK_TEXT("v c", "aXdef\n");
    fresh("abcdef\n"); feed("lvlohd");           CHECK_TEXT("v o", "def\n");
    fresh("ab\n"); feed("Vvd");                  CHECK_TEXT("V->v", "b\n");
    fresh("a\nb\nc\n"); feed("Vjyjp");           CHECK_TEXT("V y p", "a\nb\na\nb\nc\n");
    fresh("abc\n"); feed("vld"); feed("u");      CHECK_TEXT("v d u", "abc\n");
    fresh("abc\n"); feed("vl\x1b");              CHECK_INT("v esc", ed_mode(), M_NORMAL);
    fresh("ab cd\n"); feed("vwd");               CHECK_TEXT("v w d", "d\n");
    fresh("a\nb\n"); feed("vjjx"); ed_render();  CHECK_TEXT("v j x", "\n");
    fresh("a\nb\nc\n"); feed("vj"); ed_render(); CHECK_INT("visual mode", ed_mode(), M_VISUAL);
    /* paging */
    { char big2[6000]; int n = 0, L;
      for (L = 1; L <= 100; L++) n += sprintf(big2 + n, "%d\n", L);
      fresh(big2); feed("\x04"); CHECK_INT("^D", ed_cursor() > 0, 1);
      { int c1 = (int)ed_cursor(); feed("\x15"); CHECK_INT("^U back", ed_cursor(), 0); (void)c1; }
      feed("\x06"); { int c2 = (int)ed_cursor(); CHECK_INT("^F moves", c2 > 20, 1); feed("\x02"); CHECK_INT("^B back", ed_cursor(), 0); }
      feed("3\x05"); ed_render(); CHECK_INT("^E cursor follows", ed_cursor() >= 6, 1);
      feed("\x19\x19\x19"); ed_render(); CHECK_INT("^Y keeps cursor", ed_cursor() < 100, 1);
    }

    /* large yank / paste / undo (the yank register and the undo data live in the aux area of the store) */
    {
        static char src[3001]; char want[4001]; int L, n = 0;
        for (L = 1; L <= 80; L++) n += sprintf(src + n, "row%d\n", L);          /* about 470 bytes: more than the old 384-byte yank, within the 512-byte undo log */
        fresh(src);
        feed("80yy"); CHECK_INT("big yank length ok", strlen(ed_msg()), 0);
        feed("G"); feed("p");
        { char t[4001]; txt(t); total++; if (strlen(t) != 2 * (size_t)n) { fails++; printf("FAIL big paste length %d\n", (int)strlen(t)); } }
        feed("u");
        { char t[4001]; txt(t); total++; if (strcmp(t, src) != 0) { fails++; printf("FAIL big paste undo\n"); } }
        feed("\x12");
        { char t[4001]; txt(t); total++; if (strlen(t) != 2 * (size_t)n) { fails++; printf("FAIL big paste redo\n"); } }
        strcpy(want, "");
        fresh("abc\ndef\n"); feed("yyjp"); CHECK_TEXT("yank paste still works", "abc\ndef\nabc\n");
        feed("uu"); CHECK_TEXT("undo twice safe", "abc\ndef\n");
    }
    fresh("l1\nl2\nl3\nl4\n"); feed("jmajj"); feed("d'a"); CHECK_TEXT("d'a", "l1\n");
    fresh("l1\nl2\nl3\nl4\n"); feed("jmaGd'a"); CHECK_TEXT("d'a up", "l1\n");
    fresh("abcdef\n"); feed("lmallll"); feed("d`a"); CHECK_TEXT("d`a", "af\n");
    fresh("abcdef\n"); feed("lllmahh"); feed("y`a$p"); CHECK_TEXT("y`a", "abcdefbc\n");
    fresh("ab\ncdef\nxyz\n"); feed("2$"); CHECK_INT("2$", ed_cursor(), 6);
    fresh("ab\ncdef\nxyz\n"); feed("9$"); CHECK_INT("9$ out of range stays", ed_cursor(), 0);
    fresh("a\nb\nc\nd\n"); feed("G"); feed("''"); CHECK_INT("'' after G", ed_cursor(), 0); feed("''"); CHECK_INT("'' back", ed_cursor(), 6);
    fresh("a\nb\nc\nd\n"); feed("jj"); feed("gg"); feed("``"); CHECK_INT("`` after gg", ed_cursor(), 4);
    fresh("a\nb\n\nc\nd\n\n\ne\n"); feed("}"); CHECK_INT("}", ed_cursor(), 4); feed("}"); CHECK_INT("} 2", ed_cursor(), 9); feed("}"); CHECK_INT("} end", ed_cursor(), 11);
    feed("{"); CHECK_INT("{", ed_cursor(), 10); feed("{"); CHECK_INT("{ 2", ed_cursor(), 4); feed("{"); feed("{"); CHECK_INT("{ top", ed_cursor(), 0);
    fresh("a\nb\n\nc\n"); feed("d}"); CHECK_TEXT("d}", "\nc\n"); fresh("a\nb\n\nc\n"); feed("2}"); CHECK_INT("2} end", ed_cursor(), 5);
    fresh("abcdef\nxy\n"); feed("lRXY\x1b"); CHECK_TEXT("R", "aXYdef\nxy\n"); feed("jR123\x1bu"); CHECK_TEXT("R undo", "aXYdef\nxy\n");
    fresh("ab\ncd\n"); feed("RXYZ\x1b"); CHECK_TEXT("R at eol appends", "XYZ\ncd\n"); feed("j0."); CHECK_TEXT("R dot", "XYZ\nXYZ\n");
    fresh("Hello World\nhello\n"); feed(":s/WORLD/x/\r"); CHECK_TEXT("no ic", "Hello World\nhello\n");
    feed(":set ic\r:s/WORLD/x/\r"); CHECK_TEXT("ic", "Hello x\nhello\n"); feed("j:s/[A-Z]*/_/\r"); CHECK_TEXT("ic set", "Hello x\n_\n");
    feed(":set noic\r"); feed("k:s/HELLO/y/\r"); CHECK_TEXT("noic", "Hello x\n_\n"); feed(":set ic\rgg/HELLO\r"); CHECK_INT("ic search", ed_cursor(), 0);
    fresh("a1\nb\na2\nc\na3\n"); feed("G?a\r"); CHECK_INT("? back", ed_cursor(), 5); feed("n"); CHECK_INT("? n back", ed_cursor(), 0); feed("N"); CHECK_INT("? N fwd", ed_cursor(), 5);
    fresh("a1\nb\na2\n"); feed("/a\r"); feed("n"); feed("?b\r"); CHECK_INT("? after /", ed_cursor(), 3);
    fresh("hello world foo\nabc def\n"); feed("gUw"); CHECK_TEXT("gUw", "HELLO world foo\nabc def\n"); feed("wgUU"); CHECK_TEXT("gUU", "HELLO WORLD FOO\nabc def\n");
    feed("guiw"); CHECK_TEXT("guiw", "HELLO world FOO\nabc def\n"); feed("g~~"); CHECK_TEXT("g~~", "hello WORLD foo\nabc def\n");
    feed("j0vlU"); CHECK_TEXT("v U", "hello WORLD foo\nABc def\n"); feed("Vu"); CHECK_TEXT("V u", "hello WORLD foo\nabc def\n");
    fresh("aBc dEf\n"); feed("3~"); CHECK_TEXT("3~", "AbC dEf\n"); feed("gUgU"); CHECK_TEXT("gUgU", "ABC DEF\n"); feed("u"); CHECK_TEXT("undo gU", "AbC dEf\n");
    fresh("abc\ndef\nghi\n"); feed("jvl"); ed_render(); CHECK_INT("render visual (no overflow)", ed_mode(), M_VISUAL); feed("k"); ed_render(); feed("jjj"); ed_render(); feed("\x1b");
    /* marks */
    fresh("one two\nthree four\nfive\n"); feed("wma"); feed("j0"); feed("`a"); CHECK_INT("mark `a", ed_cursor(), 4);
    feed("jj'a"); CHECK_INT("mark 'a", ed_cursor(), 0);
    fresh("one two\nthree four\nfive\n"); feed("jwmb"); feed("gg"); feed("ix\x1b"); feed("`b"); CHECK_INT("mark shifts on insert", ed_cursor(), 15);
    feed("gg"); feed("dd"); feed("`b"); CHECK_INT("mark shifts on delete", ed_cursor(), 6);
    fresh("abc\n"); feed("`z"); CHECK_INT("unset mark", ed_cursor(), 0);
    fresh("f one\nx\n"); feed("mfjmt"); feed("gg`t"); CHECK_INT("f/t as mark names", ed_cursor(), 6);
    /* space BS + - Enter */
    fresh("abc\n  def\nxyz\n"); feed("  "); CHECK_INT("space", ed_cursor(), 2);
    feed("\x08"); CHECK_INT("backspace", ed_cursor(), 1);
    feed("+"); CHECK_INT("+", ed_cursor(), 6); feed("j-"); CHECK_INT("-", ed_cursor(), 6);
    feed("\r"); CHECK_INT("enter", ed_cursor(), 10); feed("2-"); CHECK_INT("2-", ed_cursor(), 0);
    fresh("a\nb\nc\nd\n"); feed("d+"); CHECK_TEXT("d+", "c\nd\n");
    fresh("a\nb\nc\nd\n"); feed("jjd-"); CHECK_TEXT("d-", "a\nd\n");
    fresh("a\nb\nc\nd\n"); feed("d\r"); CHECK_TEXT("d enter", "c\nd\n");
    fresh("abcd\n"); feed("ld "); CHECK_TEXT("d space", "acd\n");
    fresh("abcd\n"); feed("$d\x08"); CHECK_TEXT("d BS", "abd\n");
    fresh("one\ntwo\nthree\n"); feed("\"ayyj\"byyjp"); CHECK_TEXT("reg p unnamed", "one\ntwo\nthree\ntwo\n");
    fresh("one\ntwo\nthree\n"); feed("\"ayyj\"byyG\"ap\"bp"); CHECK_TEXT("reg a b", "one\ntwo\nthree\none\ntwo\n");
    fresh("one\ntwo\nthree\n"); feed("\"ayyj\"Ayyj\"ap"); CHECK_TEXT("reg append", "one\ntwo\nthree\none\ntwo\n");
    fresh("ab cd\n"); feed("\"xdwx\"xP"); CHECK_TEXT("reg xdw", "ab d\n");
    fresh("ab cd\n"); feed("\"zp"); CHECK_TEXT("reg empty", "ab cd\n");
    fresh("a1 b2\n"); feed("vl\"qyw\"qp"); CHECK_TEXT("reg visual", "a1 ba12\n");
    { int q; fresh("0123456789012345678901234567890123456789\n"); feed("\"ayy"); for (q = 0; q < 40; q++) feed("\"Ayy"); CHECK_INT("reg full ok", ed_cursor(), 0); feed("\"bYG\"ap"); }
    fresh("a1\nb2\nc3\nd4\n"); feed("qaA!\033jq@a"); CHECK_TEXT("macro", "a1!\nb2!\nc3\nd4\n"); feed("@@"); CHECK_TEXT("macro @@", "a1!\nb2!\nc3!\nd4\n");
    fresh("x\nx\nx\nx\nx\n"); feed("qaIy\033jq3@a"); CHECK_TEXT("macro count", "yx\nyx\nyx\nyx\nx\n"); feed("u"); 
    fresh("ab\n"); feed("qaxq"); CHECK_TEXT("macro rec", "b\n"); feed("@a"); CHECK_TEXT("macro play", "\n"); feed("@z"); CHECK_TEXT("macro none", "\n");
    fresh("a b c d e\n"); feed("qadwqqAxq@a"); CHECK_TEXT("macro appended", " d e\n");
    fresh("  ab\ncd\n"); feed(":set ai\r"); feed("A\ree\033"); CHECK_TEXT("ai enter", "  ab\n  ee\ncd\n");
    fresh("\tab\ncd\n"); feed(":set ai\r"); feed("ox\033Oy\033"); CHECK_TEXT("ai o O", "\tab\n\ty\n\tx\ncd\n");
    fresh("  ab\n"); feed("ox\033"); CHECK_TEXT("noai o", "  ab\nx\n");
    fresh("  ab\n"); feed(":set ai\r"); feed("llli\rZ\033"); CHECK_TEXT("ai mid", "  a\n  Zb\n");
    fresh("abcd\nefgh\nijkl\n"); feed("l\x16jjld"); CHECK_TEXT("blk d", "ad\neh\nil\n"); CHECK_INT("blk d mode", ed_mode(), 0); feed("u"); CHECK_TEXT("blk d undo", "abcd\nefgh\nijkl\n");
    fresh("ab\ncd\nef\n"); feed("\x16jjIX\033"); CHECK_TEXT("blk I", "Xab\nXcd\nXef\n"); feed("u"); CHECK_TEXT("blk I undo", "ab\ncd\nef\n");
    fresh("ab\ncd\nef\n"); feed("\x16jjAX\033"); CHECK_TEXT("blk A", "aXb\ncXd\neXf\n");
    fresh("abc\ndef\n"); feed("\x16jlcZ\033"); CHECK_TEXT("blk c", "Zc\nZf\n");
    fresh("abcd\nx\nabcd\n"); feed("ll\x16jjld"); CHECK_TEXT("blk short", "ab\nx\nab\n");
    fresh("ab\nc\nef\n"); feed("l\x16jjAX\033"); CHECK_TEXT("blk A pad", "abX\nc X\nefX\n");
    fresh("ab\ncd\n"); feed("\x16\x16"); CHECK_INT("blk toggle", ed_mode(), 0);
    fresh("a\nb\nc\nd\ne\n"); feed(":2,3d\r"); CHECK_TEXT("ex d", "a\nd\ne\n"); feed("P"); CHECK_TEXT("ex d yank", "a\nb\nc\nd\ne\n");
    fresh("a\nb\nc\nd\ne\n"); feed(":2,$d\r"); CHECK_TEXT("ex 2,$d", "a\n"); feed("u"); CHECK_TEXT("ex d undo", "a\nb\nc\nd\ne\n");
    fresh("aa\naa\naa\n"); feed(":2,3s/a/b/g\r"); CHECK_TEXT("ex range s", "aa\nbb\nbb\n"); feed(":%s/b/c/\r"); CHECK_TEXT("ex %s", "aa\ncb\ncb\n");
    fresh("x1\ny\nx2\nz\nx3\n"); feed(":g/x/d\r"); CHECK_TEXT("ex g d", "y\nz\n"); feed("u"); CHECK_TEXT("ex g undo", "x1\ny\nx2\nz\nx3\n");
    fresh("x1\ny\nx2\nz\nx3\n"); feed(":v/x/d\r"); CHECK_TEXT("ex v d", "x1\nx2\nx3\n");
    fresh("x1\ny\nx2\nz\nx3\n"); feed(":g/x/s/x/Q/\r"); CHECK_TEXT("ex g s", "Q1\ny\nQ2\nz\nQ3\n");
    fresh("ab\nb\nab\n"); feed(":g/a/s//Z/\r"); CHECK_TEXT("ex g s//", "Zb\nb\nZb\n");
    fresh("a\nb\nc\n"); feed(":2\r"); CHECK_INT("ex goto", ed_cursor(), 2); feed(":$\r"); CHECK_INT("ex goto $", ed_cursor(), 4);
    fresh("f(a, \"bc d\") x\n"); feed("fbvi\"d"); CHECK_TEXT("vi\"", "f(a, \"\") x\n");
    fresh("f(a, \"bc d\") x\n"); feed("favi(y$p"); CHECK_TEXT("vi( y", "f(a, \"bc d\") xa, \"bc d\"\n");
    fresh("one two three\n"); feed("wvawd"); CHECK_TEXT("vaw", "one three\n");
    fresh("one two\n"); feed("viwc"); feed("Z\x1b"); CHECK_TEXT("viw c", "Z two\n");
    fresh("f(a)\n"); feed("fava(\x1b"); CHECK_INT("esc after va(", ed_mode(), M_NORMAL);
    fresh("abc\n"); feed("viq"); CHECK_INT("vi + bad key", ed_mode(), M_VISUAL);
    fresh("a\n b\n  c\nd\n"); feed("3J"); CHECK_TEXT("3J", "a b c\nd\n");
    fresh("a\n b\nc\n"); feed("gJ"); CHECK_TEXT("gJ", "a b\nc\n"); feed("u"); CHECK_TEXT("gJ undo", "a\n b\nc\n");
    fresh("a\nb\n"); feed("5J"); CHECK_TEXT("5J clamp", "a b\n");
    fresh("abcdef\nxy\n"); feed("4|"); CHECK_INT("4|", ed_cursor(), 3); feed("20|"); CHECK_INT("20| clamp", ed_cursor(), 5); feed("j|"); CHECK_INT("|", ed_cursor(), 7);
    { char b[200]; FILE *bf;
      fresh("one\ntwo\nthree\n"); feed("j:!dir /w\r"); CHECK_INT(":! no name", ed_quit(), 0);
      fresh("one\ntwo\nthree\n"); feed(":w bang.txt\r"); feed("jj:!dir /w\r"); CHECK_INT(":! quits", ed_quit(), 1);
      bf = fopen("VIMICMD.BAT", "rb"); b[0] = 0; if (bf) { size_t m = fread(b, 1, sizeof b - 1, bf); b[m] = 0; fclose(bf); }
      total++; if (strcmp(b, "dir /w\r\npause\r\nV +3 bang.txt\r\n")) { fails++; printf("FAIL :! batch: %s\n", b); } }
    /* :r file (the file has CRLF and no final newline) */
    { FILE *rf = fopen("r_in.txt", "wb"); fputs("X1\r\nX2", rf); fclose(rf); }
    fresh("abc\ndef\n"); feed(":r r_in.txt\r");
    CHECK_TEXT(":r", "abc\nX1\nX2\ndef\n"); CHECK_INT(":r cursor", ed_cursor(), 4);
    feed("u"); CHECK_TEXT(":r undo", "abc\ndef\n");
    fresh("abc\ndef\n"); feed("j:r r_in.txt\r"); CHECK_TEXT(":r last line", "abc\ndef\nX1\nX2\n");
    fresh("abc\n"); feed(":r nonexist.txt\r"); CHECK_TEXT(":r missing", "abc\n");
    /* text objects: quotes and brackets */
    fresh("f(a, \"bc d\") x\n"); feed("fbci\"Z\x1b"); CHECK_TEXT("ci\"", "f(a, \"Z\") x\n");
    fresh("f(a, \"bc d\") x\n"); feed("fbda\""); CHECK_TEXT("da\"", "f(a, ) x\n");
    fresh("f(a, \"bc d\") x\n"); feed("fadi("); CHECK_TEXT("di(", "f() x\n");
    fresh("f(a, \"bc d\") x\n"); feed("f)da("); CHECK_TEXT("da( on )", "f x\n");
    fresh("f(a(b)c)\n"); feed("fbdib"); CHECK_TEXT("di( nested", "f(a()c)\n");
    fresh("f(a(b)c)\n"); feed("fcdi("); CHECK_TEXT("di( outer", "f()\n");
    fresh("{\n  x;\n}\n"); feed("jdi{"); CHECK_TEXT("di{ multi-line", "{\n}\n");
    fresh("a <b c> d\n"); feed("fbyi<$p"); CHECK_TEXT("yi<", "a <b c> db c\n");
    fresh("abc\n"); feed("di("); CHECK_TEXT("di( none", "abc\n");
#ifdef MZV_POS32
    /* files larger than 64KB (host only: 32 bit positions) */
    {
        static char big[200000]; pos_t n = 0, k, got; int L;
        for (L = 1; L <= 4000; L++) n += (pos_t)sprintf(big + n, "line %d the quick brown fox jumps over\n", L);
        ed_init(); ed_set_text(big);
        total++; if (n < 70000) { fails++; printf("FAIL big: test file too small %lu\n", (unsigned long)n); }
        feed("G"); CHECK_INT("big G line", ed_cursor() >= n - 50, 1);
        feed("dd"); feed("gg"); feed("3dd");
        feed("G");  feed("ox\x1b");
        { static char o[200000]; got = ed_text((u8 *)o, 190000);
          /* expected: lines 4..3999 then x */
          k = 0; for (L = 1; L <= 4000; L++) { char b[64]; int m = sprintf(b, "line %d the quick brown fox jumps over\n", L);
              if (L >= 4 && L <= 3999) { memcpy(big + k, b, (size_t)m); k += (pos_t)m; } }
          k += (pos_t)sprintf(big + k, "x\n");
          total++; if (got != k || memcmp(o, big, k)) { fails++; printf("FAIL big edit: got %lu want %lu\n", (unsigned long)got, (unsigned long)k); } }
        feed("100Gx");  CHECK_INT("big 100G", ed_cursor() > 3000, 1);
        feed("ggjjjdd:u"); 
    }
#endif
    printf("%d/%d passed\n", total - fails, total);
    return fails != 0;
}
