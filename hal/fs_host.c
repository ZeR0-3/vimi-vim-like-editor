/* fs_host.c - stdio backend with the same CRLF / ^Z conventions as the CP/M backend */
#include <stdio.h>
#include "fs.h"
#include "store.h"
#include "text.h"
pos_t fs_load(const char *name, pos_t max)
{
    FILE *f = fopen(name, "rb");
    int c, n = 0;
    u8 b;
    if (!f) return FS_NOFILE;
    tx_load_begin();
    while ((c = fgetc(f)) != EOF) {
        if (c == 0x1A || c == 0) break;           /* CP/M end of file (^Z) or NUL padding */
        if (c == '\r') continue;                   /* CRLF -> LF */
        if (n >= (int)max) { fclose(f); return FS_TOOBIG; }
        b = (u8)c;
        tx_load_chunk((pos_t)n, &b, 1);
        st_write((pos_t)n, &b, 1);
        n++;
    }
    fclose(f);
    return (pos_t)n;
}
int fs_stream(const char *name, int (*sink)(const u8 *buf, u8 n))
{
    FILE *f = fopen(name, "rb");
    int c;
    u8 b[64], k = 0;
    if (!f) return 1;
    while ((c = fgetc(f)) != EOF) {
        if (c == 0x1A || c == 0) break;
        if (c == '\r') continue;
        b[k++] = (u8)c;
        if (k == 64) { if (!sink(b, k)) { fclose(f); return 2; } k = 0; }
    }
    fclose(f);
    if (k && !sink(b, k)) return 2;
    return 0;
}
int fs_save(const char *name, pos_t len)
{
    FILE *f = fopen(name, "wb");
    pos_t i;
    u8 b;
    if (!f) return -1;
    for (i = 0; i < len; i++) {
        tx_read(&b, i, 1);
        if (b == '\n') fputc('\r', f);             /* LF -> CRLF */
        fputc(b, f);
    }
    fclose(f);
    return 0;
}

int fs_exec(const char *cmd, u8 wait)
{
    (void)cmd; (void)wait;
    return 0xFE;
}

int fs_bat(const char *cmd, const char *file, u16 line)
{
    FILE *f = fopen("VIMICMD.BAT", "wb");
    if (!f) return -1;
    fprintf(f, "%s\r\npause\r\nV +%u %s\r\n", cmd, (unsigned)line, file);
    fclose(f);
    return 0;
}
void fs_erase(const char *name) { remove(name); }
