#!/bin/bash
# tools/csize.sh : bytes of compiled C per function in core/editor.c (Z80 build flags) - what is left to convert to asm
cd "$(dirname "$0")/.."
export ZCCCFG=$Z88DK_PATH/lib/config; export PATH=$Z88DK_PATH/bin:$PATH
D=/tmp/csize; rm -rf $D; mkdir -p $D
zcc +cpm -compiler=sccz80 -O3 -unsigned -DMZV_POS32 -DTX_ASM -DR_ASM -DU_ASM -DM_ASM -Icore -Ihal -a -o $D/editor.asm core/editor.c 2>&1 | grep -i " error"
(cd $D && z88dk-z80asm -l editor.asm >/dev/null 2>&1)
python3 - <<'PY'
import re
cur=None; sizes={}
for l in open('/tmp/csize/editor.lis'):
    lab=re.match(r'^\s*\d+\s+\._(\w+)\s*$',l)
    if lab: cur=lab.group(1); sizes.setdefault(cur,0); continue
    m=re.match(r'\s*\d+\s+([0-9A-Fa-f]{4})\s+([0-9A-Fa-f]{2,})\s',l)
    if m and cur: sizes[cur]+=len(m.group(2))//2
it=sorted(sizes.items(), key=lambda x:-x[1])
print('total',sum(sizes.values()),'bytes in',len([1 for k,v in it if v]),'functions')
print(' '.join('%s:%d'%(k,v) for k,v in it if v>=60))
PY
