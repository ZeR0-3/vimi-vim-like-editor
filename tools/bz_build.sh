#!/bin/bash
# VIMI build. Two memory regions: low code 0100h-9FFFh (bank 5 A000-BFFF is the store window) and
# "far" cold code (SECTION code_far, '#pragma codeseg code_far') + BSS in bank 6 (C000h-DFFFh, stack at DFxx grows down).
# The result VIMI.COM = low image, zero padding up to C000h, far image.  Needs Z88DK_PATH / ZCCCFG / PATH set.
cd "$(dirname "$0")/.."
OUT=${OUT:-/tmp/v}; mkdir -p $OUT
SRC="core/editor.c hal/sys_z80.asm hal/kbd_isr.asm hal/keytab.asm hal/vram_row.asm hal/store_z80.asm hal/pal.asm hal/text_z80.asm hal/render_z80.asm hal/ulog_z80.asm hal/store_file_z80.asm hal/nav_z80.asm hal/regex_z80.asm hal/marks_z80.asm hal/exec_z80.asm hal/normal_z80.asm hal/op_z80.asm hal/key_z80.asm hal/visual_z80.asm hal/insert_z80.asm hal/edit_z80.asm hal/undo_z80.asm hal/ex_z80.asm hal/block_z80.asm hal/screen_z80.asm hal/file_z80.asm"
[ -n "$CRENDER" ] && { EXTRA="$EXTRA -DC_RENDER"; SRC="${SRC/ hal\/screen_z80.asm/}"; }   # reference build: the C renderer
build() {   # $1 = BSS origin.  Fails (and leaves no VIMI.COM behind) if the compiler / assembler / linker fails.
  rm -f $OUT/VIMI.COM $OUT/VIMI_HIMEM.bin
  zcc +cpm -compiler=sccz80 -O3 -unsigned -DMZV_POS32 -DTX_ASM -DR_ASM -DU_ASM -DM_ASM $EXTRA \
    -pragma-define:CRT_ORG_FAR=0xC000 -pragma-define:__crt_org_bss=$1 \
    -pragma-define:CRT_ENABLE_STDIO=0 -pragma-define:CLIB_OPEN_MAX=0 -Icore -Ihal \
    -o $OUT/VIMI.COM $SRC -m > $OUT/build.log 2>&1
  rc=$?
  grep -v Wconversion $OUT/build.log | grep -v "^\s*\^" | grep -i "error"
  if [ $rc -ne 0 ] || [ ! -s $OUT/VIMI.COM ]; then echo "BUILD FAILED (zcc exit $rc, see $OUT/build.log)"; rm -f $OUT/VIMI.COM; exit 1; fi
}
build 0xD000
FAR=0; [ -f $OUT/VIMI_HIMEM.bin ] && FAR=$(stat -c %s $OUT/VIMI_HIMEM.bin)     # (no far code left = no such file)
BSS=$(printf '0x%X' $(( (0xC000 + FAR + 0xF) & ~0xF )))
build $BSS                                        # BSS right after the far code
LOW=$(stat -c %s $OUT/VIMI.COM)
python3 - "$OUT" <<'PY' || exit 1
import sys
o=sys.argv[1]
import os
low=open(o+'/VIMI.COM','rb').read(); far=open(o+'/VIMI_HIMEM.bin','rb').read() if os.path.exists(o+'/VIMI_HIMEM.bin') else b''
assert 0x100+len(low) <= 0xA000, 'low image reaches the store window'
if far: open(o+'/VIMI.COM','wb').write(low+bytes(0xC000-0x100-len(low))+far)      # (without far code the file is just the low image)
PY
# Stack room: SP starts at about DFAAh under LSX-Dodgers (measured) and grows down towards the end of the BSS.
# Measured peak use is about 165 bytes (EXTRA=-DSTKDBG build, :stk); refuse to build with less than STKMIN bytes of room.
BEND=$(grep "__BSS_END_tail" $OUT/VIMI.map | sed 's/.*= \$\([0-9A-Fa-f]*\).*/\1/')
ROOM=$(( 0xDFAA - 0x$BEND ))
if [ "$ROOM" -lt "${STKMIN:-256}" ]; then echo "ERROR: stack room $ROOM bytes (BSS ends $BEND) is below ${STKMIN:-256}"; rm -f $OUT/VIMI.COM; exit 1; fi
echo "low=$LOW (ends $(printf '%X' $((0x100+LOW))), free below A000: $((0xA000-0x100-LOW)))  far=$FAR  BSS=$BSS..$BEND  stack room=$ROOM  COM=$(stat -c %s $OUT/VIMI.COM)"
