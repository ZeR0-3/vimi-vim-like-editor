/* text_gap.c - text as a gap buffer inside the flat store (store.h). */
#include "text.h"
#include "store.h"

static pos_t gs, ge;           /* gap = [gs,ge) */

#define ECAP() ((pos_t)(st_cap() - TX_AUX))      /* the last TX_AUX bytes of the store are the aux area */
void tx_reset(void) { gs = 0; ge = ECAP(); }
void tx_adopt(pos_t n) { gs = n; ge = ECAP(); }
pos_t tx_len(void) { return (pos_t)(ECAP() - (ge - gs)); }
pos_t tx_cap(void) { return ECAP(); }
void tx_aux_put(u16 off, const u8 *src, u16 n) { st_write((pos_t)(ECAP() + off), src, n); }
void tx_aux_get(u8 *dst, u16 off, u16 n) { st_read(dst, (pos_t)(ECAP() + off), n); }
void tx_aux_move(u16 dst, u16 src, u16 n) { st_move((pos_t)(ECAP() + dst), (pos_t)(ECAP() + src), n); }
pos_t tx_free(void) { return (pos_t)(ge - gs); }
u8 tx_get(pos_t i) { return i < gs ? st_get(i) : st_get((pos_t)(i + (ge - gs))); }

static void gapto(pos_t p)
{
    pos_t n;
    if (p < gs) {
        n = (pos_t)(gs - p);
        st_move((pos_t)(ge - n), p, n);
        gs = p;
        ge = (pos_t)(ge - n);
    } else if (p > gs) {
        n = (pos_t)(p - gs);
        st_move(gs, ge, n);
        gs = (pos_t)(gs + n);
        ge = (pos_t)(ge + n);
    }
}

void tx_read(u8 *dst, pos_t p, pos_t n)
{
    pos_t k;
    if (p < gs) {
        k = (pos_t)(gs - p);
        if (k > n) k = n;
        st_read(dst, p, k);
        dst += k; p = (pos_t)(p + k); n = (pos_t)(n - k);
    }
    if (n) st_read(dst, (pos_t)(p + (ge - gs)), n);
}

u8 tx_ins(pos_t p, const u8 *src, pos_t n)
{
    if ((pos_t)(ge - gs) < n) return 0;
    gapto(p);
    st_write(gs, src, n);
    gs = (pos_t)(gs + n);
    return 1;
}

void tx_del(pos_t p, pos_t n)
{
    gapto(p);
    ge = (pos_t)(ge + n);
}

pos_t tx_find(pos_t p, pos_t end, u8 c)
{
    pos_t g, q, e1;
    g = (pos_t)(ge - gs);
    if (p < gs) {
        e1 = end < gs ? end : gs;
        q = st_findb(p, e1, c);
        if (q < e1) return q;
        if (end <= gs) return end;
        p = gs;
    }
    q = st_findb((pos_t)(p + g), (pos_t)(end + g), c);
    return (pos_t)(q - g);
}

pos_t tx_rfind(pos_t p, u8 c)
{
    pos_t g, q;
    g = (pos_t)(ge - gs);
    if (p > gs) {
        q = st_rfindb((pos_t)(p + g), (pos_t)(gs + g), c);
        if (q != POS_NONE) return (pos_t)(q - g);
        p = gs;
    }
    return st_rfindb(p, 0, c);
}

pos_t tx_count(pos_t a, pos_t b, u8 c)
{
    pos_t g, n, e1;
    g = (pos_t)(ge - gs);
    n = 0;
    if (b <= a) return 0;
    if (a < gs) {
        e1 = b < gs ? b : gs;
        n = st_countb(a, e1, c);
        if (b <= gs) return n;
        a = gs;
    }
    return (pos_t)(n + st_countb((pos_t)(a + g), (pos_t)(b + g), c));
}

pos_t tx_nthline(pos_t n)
{
    pos_t p, e, len;
    p = 0;
    len = tx_len();
    while (n > 1) {
        e = tx_find(p, len, '\n');
        if ((pos_t)(e + 1) >= len) break;
        p = (pos_t)(e + 1);
        n--;
    }
    return p;
}

void tx_load_begin(void) {}
void tx_load_chunk(pos_t off, const u8 *buf, u16 k) { (void)off; (void)buf; (void)k; }
