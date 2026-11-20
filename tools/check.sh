#!/bin/bash
# tools/check.sh [FUZZSEED]  -- full check before a delivery: build (with stack/low-size guards), host tests (both POS widths),
# then the Z80 build in the emulator against the host core: default + tools/scen/*.txt + a fuzz run. Stops at the first failure.
# SCEN="DEFAULT tools/scen/visual.txt" limits the emulator part to those scenario files (DEFAULT = the built-in list).
# SCREEN=1 adds the screen comparison (about 8 minutes).
# BIG=1 adds the >64KB runs (about 12 more minutes; needs /tmp/M.TXT = the first 1500 lines of BIG.TXT).
# Needs: Z88DK_PATH exported, /tmp/C.TXT /tmp/BIG.TXT /tmp/BR.TXT, the emulator in /home/claude/emu.
set -e
# A run counts only if it finished: every log must end with "ALL OK" (a crash, a timeout or a DIFF all fail the check).
require_ok() { local f r=0; for f in "$@"; do if ! tail -n 1 "$f" 2>/dev/null | grep -q "^ALL OK"; then echo "FAILED: $f"; grep -h -A2 "^DIFF\|Error\|Traceback" "$f" | head -12; r=1; fi; done; return $r; }
cd "$(dirname "$0")/.."
export ZCCCFG=$Z88DK_PATH/lib/config; export PATH=$Z88DK_PATH/bin:$PATH
SEED=${1:-1}
echo "== build";  bash tools/bz_build.sh
echo "== host tests"
for f in "-DMZV_POS32 -DHOST_CAP=400000u" ""; do
  gcc -std=c99 -DTX_NBMAX=400 $f -fsanitize=address,undefined -Icore tests/test_core.c core/editor.c core/text_blk.c hal/hal_host.c hal/fs_host.c hal/store_host.c -o /tmp/tb
  (cd /tmp && ./tb > /tmp/check_host.log; tail -n 1 /tmp/check_host.log; ! grep -q FAIL /tmp/check_host.log) || { grep -A3 FAIL /tmp/check_host.log | head -20; exit 1; }
done
gcc -std=c99 -DTX_NBMAX=400 -DMZV_POS32 -DHOST_CAP=400000u -Icore tools/hostrun.c core/editor.c core/text_blk.c hal/hal_host.c hal/fs_host.c hal/store_host.c -o /tmp/hostrun
bash tools/mkdisk.sh /tmp/check.d88 /tmp/C.TXT /tmp/BIG.TXT /tmp/BR.TXT >/dev/null
python3 tools/emu_fuzz.py $SEED 40 > /tmp/check_fuzz.txt
echo "== emulator (parallel)"
rm -f /tmp/check_list
( cd /tmp; for s in ${SCEN:-DEFAULT tools/scen/features.txt tools/scen/undo.txt tools/scen/move.txt tools/scen/ctrl.txt tools/scen/ops1.txt tools/scen/ops2.txt tools/scen/ops3.txt tools/scen/visual.txt tools/scen/insert.txt tools/scen/edit.txt tools/scen/edit2.txt tools/scen/undo2.txt tools/scen/ex.txt tools/scen/block.txt /tmp/check_fuzz.txt}; do
    [ "$s" = DEFAULT ] && s=""
    [ -n "$s" ] && [ "${s#/}" = "$s" ] && s=/home/claude/mzvim/$s
    n=$(basename "${s:-default}"); echo /tmp/check_$n.log >> /tmp/check_list; ( python3 /home/claude/mzvim/tools/emu_regress.py /tmp/check.d88 $s > /tmp/check_$n.log 2>&1; echo "$n: $(tail -n 1 /tmp/check_$n.log)" ) &
  done; wait )
require_ok $(cat /tmp/check_list) || exit 1
if [ -n "$SCREEN" ]; then   # SCREEN=1: the screen (pixels) of the asm renderer against a build with the C renderer, tools/scen/screen.txt
  echo "== screen"
  CRENDER=1 bash tools/bz_build.sh >/dev/null && bash tools/mkdisk.sh /tmp/check_ref.d88 /tmp/C.TXT /tmp/BIG.TXT /tmp/BR.TXT >/dev/null
  bash tools/bz_build.sh >/dev/null
  split -n l/2 tools/scen/screen.txt /tmp/check_scr_
  ( cd /tmp; for f in /tmp/check_scr_aa /tmp/check_scr_ab; do ( MZV_REF=/tmp/check_ref.d88 python3 /home/claude/mzvim/tools/emu_regress.py /tmp/check.d88 $f > $f.log 2>&1; echo "screen: $(tail -n 1 $f.log)" ) & done; wait )
    require_ok /tmp/check_scr_aa.log /tmp/check_scr_ab.log || exit 1
fi
if [ -n "$BIG" ]; then      # BIG=1: files over 64KB on the swap-file store (-sF120): /tmp/M.TXT (80KB, room to paste) and /tmp/BIG.TXT (full)
  echo "== big files"
  bash tools/mkdisk.sh /tmp/check_big.d88 /tmp/C.TXT /tmp/M.TXT /tmp/BIG.TXT >/dev/null
  ( cd /tmp
    ( MZV_FILE=M.TXT MZV_ARGS='-sF120 ' MZV_T0=15000 MZV_TAIL=20000 python3 /home/claude/mzvim/tools/emu_regress.py /tmp/check_big.d88 /home/claude/mzvim/tools/scen/mid.txt > /tmp/check_mid.log 2>&1; echo "mid.txt: $(tail -n 1 /tmp/check_mid.log)" ) &
    ( MZV_FILE=BIG.TXT MZV_ARGS='-sF120 ' MZV_T0=20000 MZV_TAIL=25000 python3 /home/claude/mzvim/tools/emu_regress.py /tmp/check_big.d88 /home/claude/mzvim/tools/scen/big.txt > /tmp/check_bigf.log 2>&1; echo "big.txt: $(tail -n 1 /tmp/check_bigf.log)" ) &
    wait )
  require_ok /tmp/check_mid.log /tmp/check_bigf.log || exit 1
fi
echo "ALL CHECKS PASSED"
