#!/bin/bash
# usage: tools/mkdisk.sh out.d88 [extra files...]   -> disk with VIMI.COM, README.TXT and the TUTOR.TXT vim tutorial
# expects /tmp/v/VIMI.COM and /tmp/v/VIMI.map from the build
set -e
cd "$(dirname "$0")/.."
out=$1; shift
S=/tmp/srcdisk; rm -rf $S; mkdir -p $S
crlf() { sed 's/\r$//; s/$/\r/' "$1" > "$S/$2"; }
crlf docs/TUTOR.TXT TUTOR.TXT
cat > $S/README.TXT <<'R'
VIMI - vim-like editor for the MZ-2500 (CP/M-80 / LSX-Dodgers)

  VIMI file                 edit a file
  VIMI -sF120 file          big file: 120KB swap file on drive F:
  VIMI TUTOR.TXT            start here: a hands-on vim tutorial (practice text)
  V file                    same as VIMI; on an older LSX it lets :!cmd run cmd and come back (newer LSX: run  ramdisk 64  first, then plain VIMI is enough)

Quit: :q!   Save and quit: :wq or ZZ.   Esc returns to NORMAL mode.
The ~ key is Shift + ^.
R
sed 's/$/\r/' $S/README.TXT > $S/R2 && mv $S/R2 $S/README.TXT
printf 'vimi $1 $2\r\nif exist vimicmd.bat vimicmd\r\n' > $S/V.BAT
cp /tmp/v/VIMI.COM $S/VIMI.COM
python3 tools/d88_put.py "$out" $S/VIMI.COM $S/V.BAT $S/README.TXT $S/TUTOR.TXT "$@" | tail -1 | cut -c1-200
