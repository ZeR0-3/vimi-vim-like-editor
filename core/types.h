/* types.h - 16bit-safe basic types (works for gcc host and z88dk sccz80) */
#ifndef MZV_TYPES_H
#define MZV_TYPES_H
typedef unsigned char u8;
typedef unsigned int  u16;   /* 16bit on Z80. On host we mask where wrap matters (buffer < 64KB). */
/* pos: byte offset / length inside the text store.  16 bit on the Z80 (store <= 64KB); define MZV_POS32 to build the core
 * with 32 bit positions (host tests for files > 64KB).  POS_NONE = "not found". */
#ifdef MZV_POS32
typedef unsigned long pos_t;
#define POS_NONE 0xFFFFFFFFul
#else
typedef u16 pos_t;
#define POS_NONE 0xFFFFu
#endif
#endif
