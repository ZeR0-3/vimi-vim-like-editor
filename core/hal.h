/* hal.h - what the core needs from the machine (video, keys). */
#ifndef MZV_HAL_H
#define MZV_HAL_H
#include "types.h"
#define SCR_COLS 80
#define SCR_ROWS 25          /* 0..23 text, 24 status */
/* attribute: bit7 BL, bit6 RV, bit2 G, bit1 R, bit0 B (MZ-2500 text attribute) */
#define AT_WHITE 0x07
#define AT_RV    0x40
void hal_init(void);                                     /* before the main loop */
void hal_exit(void);                                     /* before returning to the OS */
int  hal_getkey(void);                                   /* blocking; BDOS-style codes (ESC=1B, arrows 1C..1F, CR=0D, BS=08, DEL=12) */
void hal_scroll(int n);                                  /* hardware scroll: n lines, n>0 = content moves up (view start += n rows) */
void hal_putrow(u8 y, const u8 *chars, const u8 *attrs); /* write one full row (80 cells) */
#endif
