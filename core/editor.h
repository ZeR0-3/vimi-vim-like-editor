#ifndef MZV_EDITOR_H
#define MZV_EDITOR_H
#include "types.h"
#define M_NORMAL 0
#define M_INSERT 1
#define M_CMD    2
#define M_VISUAL 3
void ed_init(void);                       /* empty buffer */
int  ed_load(const char *name);           /* 0 ok, 1 new file, 2 too big (buffer left empty, no name) */
void ed_key(u8 k);                        /* feed one key */
void ed_render(void);                     /* update screen through hal_putrow (only changed rows) */
int  ed_quit(void);
void ed_goto(u16 n);
void ed_redraw(void);                    /* the screen was changed behind the editor's back */                      /* jump to line n (1-based) */
/* for tests */
pos_t  ed_text(u8 *out, pos_t max);           /* copy logical text (no NUL) */
pos_t  ed_cursor(void);
u8   ed_mode(void);
u8   ed_modified(void);
const char *ed_msg(void);
void ed_set_text(const char *s);
#endif
