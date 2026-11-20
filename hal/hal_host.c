/* hal_host.c - fake screen with an emulated 2048-cell VRAM + hardware scroll start; scripted keys for PC tests */
#include <string.h>
#include "hal.h"
u8 host_ch[SCR_ROWS][SCR_COLS];      /* the visible screen, rebuilt from the cell memory after each operation */
u8 host_at[SCR_ROWS][SCR_COLS];
int host_putrow_calls, host_scroll_calls;
static u8 vc[2048], va[2048];
static int start;
static const u8 *kq; static int kn, ki;
void host_keys(const u8 *k, int n) { kq = k; kn = n; ki = 0; }
int hal_getkey(void) { return ki < kn ? kq[ki++] : -1; }
static void refresh(void)
{
    int y, x, i;
    for (y = 0; y < SCR_ROWS; y++)
        for (x = 0; x < SCR_COLS; x++) {
            i = (start + y * SCR_COLS + x) & 0x7FF;
            host_ch[y][x] = vc[i];
            host_at[y][x] = va[i];
        }
}
void hal_putrow(u8 y, const u8 *chars, const u8 *attrs)
{
    int x;
    for (x = 0; x < SCR_COLS; x++) {
        int i = (start + y * SCR_COLS + x) & 0x7FF;
        vc[i] = chars[x];
        va[i] = attrs[x];
    }
    host_putrow_calls++;
    refresh();
}
void hal_scroll(int n)
{
    start = (start + n * SCR_COLS) & 0x7FF;
    start = (start + 2048) & 0x7FF;
    host_scroll_calls++;
    refresh();
}
void hal_init(void) {}
void hal_exit(void) {}
