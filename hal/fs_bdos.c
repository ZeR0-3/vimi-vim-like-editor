/* fs_bdos.c - CP/M BDOS file backend (LSX-Dodgers and other CP/M-80). Text: CRLF<->LF, ^Z terminated. */
#include <string.h>
#include <cpm.h>
#include "fs.h"
#include "store.h"
#include "text.h"

#define B_CLOSE  16
#define B_OPEN   15
#define B_DELETE 19
#define B_READ   20
#define B_WRITE  21
#define B_MAKE   22
#define B_DMA    26

static int B(u8 fn, int de)
{
    st_close();
    return bdos(fn, de);
}

static u8 fcb[36];
static u8 dma[128];
static u8 tmp[128];

static void mkfcb(const char *name)
{
    u8 i, c;
    for (i = 0; i < 36; i++) fcb[i] = 0;
    for (i = 1; i < 12; i++) fcb[i] = ' ';
    if (name[0] && name[1] == ':') {
        c = (u8)name[0];
        if (c >= 'a' && c <= 'z') c -= 32;
        fcb[0] = (u8)(c - 'A' + 1);
        name += 2;
    }
    for (i = 1; i <= 8 && *name && *name != '.'; i++, name++) {
        c = (u8)*name;
        if (c >= 'a' && c <= 'z') c -= 32;
        fcb[i] = c;
    }
    while (*name && *name != '.') name++;
    if (*name == '.') {
        name++;
        for (i = 9; i <= 11 && *name; i++, name++) {
            c = (u8)*name;
            if (c >= 'a' && c <= 'z') c -= 32;
            fcb[i] = c;
        }
    }
}

int fs_stream(const char *name, int (*sink)(const u8 *buf, u8 n))
{
    u8 i, k, c;
    int r;
    r = 0;
    mkfcb(name);
    B(B_DMA, (int)dma);
    if ((B(B_OPEN, (int)fcb) & 0xFF) == 0xFF) return 1;
    for (;;) {
        for (i = 0; i < 128; i++) dma[i] = 0x1A;
        B(B_DMA, (int)dma);
        if (B(B_READ, (int)fcb) & 0xFF) break;
        k = 0;
        for (i = 0; i < 128; i++) {
            c = dma[i];
            if (c == 0x1A || c == 0) break;
            if (c != '\r') tmp[k++] = c;
        }
        if (k && !sink(tmp, k)) { r = 2; break; }
        if (i < 128) break;
    }
    B(B_CLOSE, (int)fcb);
    return r;
}

static pos_t ld_n, ld_max;
static int ld_sink(const u8 *buf, u8 k)
{
    if ((pos_t)(ld_n + k) >= ld_max) return 0;
    tx_load_chunk(ld_n, buf, k); st_write(ld_n, buf, k); ld_n = (pos_t)(ld_n + k);
    return 1;
}

pos_t fs_load(const char *name, pos_t max)
{
    int r;
    ld_n = 0; ld_max = max;
    tx_load_begin();
    r = fs_stream(name, ld_sink);
    return r == 1 ? FS_NOFILE : r == 2 ? FS_TOOBIG : ld_n;
}

int fs_save(const char *name, pos_t len)
{
    pos_t i, got;
    u8 j, k, c, pass;
    mkfcb(name);
    B(B_DMA, (int)dma);
    B(B_DELETE, (int)fcb);
    mkfcb(name);
    if ((B(B_MAKE, (int)fcb) & 0xFF) == 0xFF) return -1;
    k = 0;
    for (i = 0; i < len; i = (pos_t)(i + got)) {
        got = (pos_t)(len - i);
        if (got > 64) got = 64;
        tx_read(tmp, i, got);
        for (j = 0; j < got; j++) {
            c = tmp[j];
            for (pass = (u8)(c == '\n' ? 2 : 1); pass; pass--) {
                dma[k++] = (c == '\n' && pass == 2) ? '\r' : c;
                if (k == 128) {
                    B(B_DMA, (int)dma);
                    if (B(B_WRITE, (int)fcb) & 0xFF) return -1;
                    k = 0;
                }
            }
        }
    }
    if (k) {
        while (k < 128) dma[k++] = 0x1A;
        B(B_DMA, (int)dma);
        if (B(B_WRITE, (int)fcb) & 0xFF) return -1;
    }
    if ((B(B_CLOSE, (int)fcb) & 0xFF) == 0xFF) return -1;
    return 0;
}

void fs_erase(const char *name)
{
    mkfcb(name);
    B(B_DMA, (int)dma);
    B(B_DELETE, (int)fcb);
}

static u8 bn;
static void bput(u8 c)
{
    dma[bn++] = c;
    if (bn == 128) { B(B_DMA, (int)dma); B(B_WRITE, (int)fcb); bn = 0; }
}
static void bstr(const char *t) { while (*t) bput((u8)*t++); }
static const u16 dv[5] = { 10000, 1000, 100, 10, 1 };
int fs_bat(const char *cmd, const char *file, u16 line)
{
    u8 i, k;
    mkfcb("VIMICMD.BAT");
    B(B_DMA, (int)dma);
    B(B_DELETE, (int)fcb);
    mkfcb("VIMICMD.BAT");
    if ((B(B_MAKE, (int)fcb) & 0xFF) == 0xFF) return -1;
    bn = 0;
    bstr(cmd);
    for (k = (u8)strlen(cmd); k < 4; k++) bput(' ');     /* the batch reader ends on lines shorter than 4 characters */
    bstr("\r\npause\r\nV +");
    for (i = 0; i < 5; i++) {
        k = (u8)(line / dv[i]);
        line %= dv[i];
        if (k || i == 4 || bn > 0 && dma[bn - 1] != '+') bput((u8)('0' + k));
    }
    bput(' ');
    bstr(file);
    bstr("\r\n");
    while (bn) bput(0x1A);
    B(B_CLOSE, (int)fcb);
    return 0;
}

#ifdef STKDBG                                   /* stack high-water mark (debug builds): :stk shows the bytes never touched */
extern u8 _BSS_END_tail;
void stk_init(void)
{
    u8 *p, here;
    for (p = &_BSS_END_tail; p < &here - 48; p++) *p = 0xA5;
}
u16 stk_free(void)
{
    u8 *p = &_BSS_END_tail;
    while (*p == 0xA5) p++;
    return (u16)(p - &_BSS_END_tail);
}
#endif
