/* hostrun: feed a key script to the editor core on the host and print the text. usage: hostrun file script
 * script escapes: \e = Esc, \r = Return, \\ = backslash; ~ ' ` etc. are plain characters */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "editor.h"
int main(int argc, char **argv)
{
    static char buf[200000]; static unsigned char out[200000];
    FILE *f = fopen(argv[1], "rb"); size_t n = f ? fread(buf, 1, sizeof buf - 1, f) : 0; const char *k = argv[2]; unsigned long m, i, j = 0;
    char *t = malloc(n + 1);
    for (i = 0; i < n; i++) if (buf[i] != '\r') t[j++] = buf[i];
    t[j] = 0;
    ed_init(); ed_set_text(t);
    while (*k) {
        if (k[0] == '\\' && k[1] == 'e') { ed_key(0x1B); k += 2; }
        else if (k[0] == '\\' && k[1] == 'v') { ed_key(0x16); k += 2; }
        else if (k[0] == '\\' && k[1] == '^' && k[2]) { ed_key((unsigned char)(k[2] & 0x1F)); k += 3; }   /* \^d = Ctrl-D */
        else if (k[0] == '\\' && k[1] == 'r') { ed_key(0x0D); k += 2; }
        else if (k[0] == '\\' && k[1] == '\\') { ed_key('\\'); k += 2; }
        else ed_key((unsigned char)*k++);
    }
    m = ed_text(out, sizeof out - 1); out[m] = 0;
    fwrite(out, 1, m, stdout);
    return 0;
}
