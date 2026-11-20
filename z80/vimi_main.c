/* vimi_main.c - VIMI.COM entry point for LSX-Dodgers / CP/M on MZ-2500 */
#include "editor.h"
#include "hal.h"
#include "store.h"
#include "fs.h"

extern void hal_clear(void);
extern u8 pal_enable;

int main(int argc, char **argv)
{
    int i;
    const char *file;
    u16 line;
    file = 0;
    line = 0;
    for (i = 1; i < argc; i++) {
        if (argv[i][0] == '-' && (argv[i][1] == 'n' || argv[i][1] == 'N')) pal_enable = 0;   /* -n: keep the OS palette */
        else if (argv[i][0] == '-' && (argv[i][1] == 's' || argv[i][1] == 'S') && argv[i][2]) { u16 kb = 0; const char *q = argv[i] + 3; while (*q >= '0' && *q <= '9') kb = (u16)(kb * 10 + (*q++ - '0')); st_select(argv[i][2], kb); }
        else if (argv[i][0] == '+') { const char *q = argv[i] + 1; while (*q >= '0' && *q <= '9') line = (u16)(line * 10 + (*q++ - '0')); }   /* +N: start on line N */
        else file = argv[i];
    }
#ifdef STKDBG
    stk_init();
#endif
    st_init();
    hal_init();
    hal_clear();
    ed_init();
    fs_erase("VIMICMD.BAT");                      /* a finished :!cmd leaves this behind */
    if (file) ed_load(file);
    if (line) ed_goto(line);
    while (!ed_quit()) {
        ed_render();
        ed_key((u8)hal_getkey());
    }
    hal_exit();
    st_exit();
    hal_clear();
    return 0;
}
