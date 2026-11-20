/* text.h - the editor's text: a logical byte sequence addressed by 0..tx_len()-1.
 * Two implementations behind it: text_gap.c (gap buffer over the flat store: host, pages, plain memory)
 * and, later, a block list for the swap-file store (fast edits far from the previous one). */
#ifndef MZV_TEXT_H
#define MZV_TEXT_H
#include "types.h"
void  tx_reset(void);                                  /* empty text */
void  tx_adopt(pos_t n);                               /* the flat store holds n bytes of text from offset 0 (after fs_load / ed_set_text) */
pos_t tx_len(void);
pos_t tx_cap(void);                                    /* largest text a load may bring in (call before tx_adopt) */
pos_t tx_free(void);                                   /* bytes that can still be inserted */
u8    tx_get(pos_t i);
void  tx_read(u8 *dst, pos_t p, pos_t n);              /* text -> main memory */
u8    tx_ins(pos_t p, const u8 *src, pos_t n);         /* insert n bytes at p; 0 if there is no room */
void  tx_del(pos_t p, pos_t n);
pos_t tx_find(pos_t p, pos_t end, u8 c);               /* first index in [p,end) holding c, else end */
pos_t tx_rfind(pos_t p, u8 c);                         /* last index in [0,p) holding c, else POS_NONE */
pos_t tx_count(pos_t a, pos_t b, u8 c);                /* number of c in [a,b) */
pos_t tx_nthline(pos_t n);                             /* start of line n (1-based); beyond the end = the last line (text ends with '\n') */
/* load hints: the file loader reports the bytes it writes at offset 0.. so per-block newline counts are known without rescanning */
void  tx_load_begin(void);
void  tx_load_chunk(pos_t off, const u8 *buf, u16 k);

/* Auxiliary area: TX_AUX bytes at the end of the store, kept by the text layer for the editor's undo data and yank
 * register (so they take no main memory).  tx_cap() already excludes it. */
#define TX_AUX 3072u
void tx_aux_put(u16 off, const u8 *src, u16 n);
void tx_aux_get(u8 *dst, u16 off, u16 n);
void tx_aux_move(u16 dst, u16 src, u16 n);
#endif
