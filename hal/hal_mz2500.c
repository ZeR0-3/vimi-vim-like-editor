/* hal_mz2500.c - MZ-2500 video (text VRAM via bank 7) and keyboard (BDOS fn 6), z88dk sccz80.
 * Video and keys do not depend on LSX/IOCS except the BDOS key read (to be replaced by direct matrix scan).
 * Code and stack must stay below E000h while the VRAM window is open; interrupts are off meanwhile. */
#include <cpm.h>
#include "hal.h"
#include "store.h"

u16 rw_adr;
const u8 *rw_chars;
const u8 *rw_attrs;
extern void vram_row(void);

u16 hw_start;                    /* text CRT-C start address (cells), 0..7FF */
extern void crtc_start(void);

static void set_start(u16 v)
{
    hw_start = v & 0x7FFu;
    crtc_start();
}

void hal_scroll(int n)
{
    set_start((u16)(hw_start + n * SCR_COLS));
}

void hal_putrow(u8 y, const u8 *chars, const u8 *attrs)
{
    rw_adr = (u16)(0xE000u + ((hw_start + (u16)y * SCR_COLS) & 0x7FFu));
    rw_chars = chars;
    rw_attrs = attrs;
    vram_row();
}

extern int kbd_get(void);
extern void kbd_install(void);
extern void kbd_remove(void);

extern void pal_on(void);
extern void pal_off(void);
void hal_init(void) { kbd_install(); pal_on(); }
extern void vram_clear(void);
void hal_exit(void)
{
    kbd_remove();
    pal_off();
    if (hw_start) {
        vram_clear();            /* blank everything first: the rotated picture must never become visible */
        set_start(0);
    }
}

int hal_getkey(void)
{
    int k;
    for (;;) {
        k = kbd_get();
        if (k) return k;
#asm
        halt
#endasm
    }
}

void hal_clear(void)
{
    st_close();
    bdos(2, 0x0C);          /* LSX console: clear screen + home */
}

/* :!cmd / :r !cmd - run an external command with the LSX E5h call.  Returns the child's result, or 0xFE when the OS cannot do it. */
extern u8 exec_ok(void);
extern u8 exec_call(const char *cmd);
int fs_exec(const char *cmd, u8 wait)
{
    static u8 r, i;
    static const char pak[] = "\r\nPress any key";
    if (!exec_ok()) return 0xFE;
    hal_exit();
    hal_clear();
    r = exec_call(cmd);
    if (r < 0xF0 && (wait || r)) {
        for (i = 0; pak[i]; i++) bdos(2, pak[i]);
        bdos(1, 0);
    }
    hal_init();
    hal_clear();
    return r;
}
