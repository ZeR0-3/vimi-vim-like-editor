/* size probe: core + stub HAL/fs, only to measure the Z80 code size */
#include "editor.h"
#include "hal.h"
#include "fs.h"
int hal_getkey(void) { return 0x1B; }
void hal_putrow(u8 y, const u8 *c, const u8 *a) { (void)y; (void)c; (void)a; }
int fs_load(const char *n, u8 *d, u16 m) { (void)n; (void)d; (void)m; return -1; }
int fs_save(const char *n, const u8 *s, u16 l) { (void)n; (void)s; (void)l; return 0; }
int main(void)
{
    ed_init();
    while (!ed_quit()) { ed_render(); ed_key((u8)hal_getkey()); }
    return 0;
}
