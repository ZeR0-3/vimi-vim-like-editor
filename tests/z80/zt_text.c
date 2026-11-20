/* test_text.c - randomized check of a tx_* implementation against a plain array model */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "text.h"
#include "store.h"
#ifndef MAXM
#define MAXM 13000
#endif
static unsigned char model[MAXM];
static unsigned long mlen;
static int fails;
static int lastop; static unsigned long lastp, lastn;
#ifdef TX_DEBUG
int tx_selfcheck(void);
void tx_dump(void);
#endif
static unsigned long rnd(unsigned long n) { return (unsigned long)rand() % n; }

static void check_all(const char *what)
{
    static unsigned char buf[MAXM];
    unsigned long i;
    if (tx_len() != mlen) { printf("FAIL %s: len %lu want %lu\n", what, (unsigned long)tx_len(), mlen); fails++; return; }
    tx_read(buf, 0, mlen);
    if (memcmp(buf, model, mlen)) { printf("FAIL %s: content differs\n", what); fails++; return; }
    for (i = 0; i < 40 && mlen; i++) {
        unsigned long p = rnd(mlen);
        if (tx_get(p) != model[p]) { printf("FAIL %s: get %lu\n", what, p); fails++; return; }
    }
}

int main(int argc, char **argv)
{
    unsigned long seed, it, p, n, i, a, b, cnt, want;
    unsigned char chunk[3000], c;
    int rounds = ZT_ROUNDS; (void)argc; (void)argv;
    for (seed = 1; seed <= (unsigned long)rounds; seed++) {
        srand((unsigned)seed);
        st_init();
        tx_reset();
        mlen = 0;
        for (it = 0; it < ZT_ITERS; it++) {
            switch (rnd(7)) {
            case 0: case 1:                                    /* insert */
                n = rnd(8) == 0 ? rnd(2500) : rnd(40);
                p = rnd(mlen + 1);
                for (i = 0; i < n; i++) chunk[i] = (unsigned char)(rnd(5) == 0 ? '\n' : 'a' + rnd(6));
                lastop = 1; lastp = p; lastn = n;
                if (tx_ins(p, chunk, n)) {
                    memmove(model + p + n, model + p, mlen - p);
                    memcpy(model + p, chunk, n);
                    mlen += n;
                }
                break;
            case 2:                                            /* delete */
                if (!mlen) break;
                p = rnd(mlen);
                n = rnd(6) == 0 ? rnd(mlen - p + 1) : rnd(30);
                if (n > mlen - p) n = mlen - p;
                lastop = 2; lastp = p; lastn = n;
                tx_del(p, n);
                memmove(model + p, model + p + n, mlen - p - n);
                mlen -= n;
                break;
            case 3:                                            /* find / rfind */
                c = (unsigned char)(rnd(2) ? '\n' : 'a' + rnd(6));
                a = rnd(mlen + 1); b = a + rnd(mlen - a + 1);
                want = b; for (i = a; i < b; i++) if (model[i] == c) { want = i; break; }
                if (tx_find(a, b, c) != want) { printf("FAIL find seed %lu it %lu\n", seed, it); fails++; }
                a = rnd(mlen + 1);
                want = (unsigned long)(pos_t)POS_NONE;
                for (i = a; i > 0; i--) if (model[i - 1] == c) { want = i - 1; break; }
                { pos_t got = tx_rfind(a, c); if (got != (pos_t)want) { printf("FAIL rfind seed %lu it %lu got %lu want %lu\n", seed, it, (unsigned long)got, want); fails++; } }
                break;
            case 4:                                            /* count */
                c = '\n';
                a = rnd(mlen + 1); b = a + rnd(mlen - a + 1);
                cnt = 0; for (i = a; i < b; i++) if (model[i] == c) cnt++;
                if (tx_count(a, b, c) != cnt) { printf("FAIL count seed %lu it %lu\n", seed, it); fails++; }
                break;
            case 5:                                            /* nth line start (model: skip min(n-1, newlines-1) newlines) */
                if (rnd(3)) { unsigned long tot = 0, k, q = 0, got, j;
                    for (j = 0; j < mlen; j++) if (model[j] == '\n') tot++;
                    n = rnd(tot + 3) + (rnd(8) == 0 ? 100000 : 0);
                    if (tot == 0 || n <= 1) want = 0;
                    else { k = n - 1; if (k > tot - 1) k = tot - 1; want = 0; for (j = 0; j < mlen && k; j++) if (model[j] == '\n') { k--; want = j + 1; } }
                    got = (unsigned long)tx_nthline((pos_t)n); (void)q;
                    if (got != want) { printf("FAIL nthline seed %lu it %lu n %lu got %lu want %lu\n", seed, it, n, got, want); fails++; }
                }
                break;
            default:                                           /* bulk delete near everything then refill */
                if (rnd(40) == 0 && mlen) { tx_del(0, mlen); mlen = 0; }
                break;
            }
#ifdef TX_DEBUG
            { int r = tx_selfcheck(); if (r) { printf("FAIL selfcheck %d seed %lu it %lu lastop %d p %lu n %lu mlen %lu\n", r, seed, it, lastop, lastp, lastn, mlen); tx_dump(); return 1; } }
#endif
            if (it % 97 == 0) check_all("periodic");
        }
        check_all("final");
        /* adopt: flat load */
        { unsigned long L = rnd(5000) + 1; static unsigned char tmp[5100];
          for (i = 0; i < L; i++) tmp[i] = (unsigned char)('a' + rnd(26));
          st_write(0, tmp, (pos_t)L); tx_adopt((pos_t)L);
          memcpy(model, tmp, L); mlen = L; 
          check_all("adopt");
          { unsigned h = (unsigned)(L / 2), LL = (unsigned)L; tx_ins(h, (const u8 *)"XY", 2); memmove(model + h + 2, model + h, LL - h); model[h] = 'X'; model[h + 1] = 'Y'; mlen += 2; }
          check_all("adopt+ins"); }
    }
    printf(fails ? "text test FAILED (%d)\n" : "text test ok\n", fails);
    return fails != 0;
}
