#!/usr/bin/env python3
"""標準LSX形式(FAT12, 512B/セクタ, 9sec/trk, 2面)の空き2DDディスクを作り、ファイルをルートに入れる。
  d88_put.py out.d88 FILE [FILE...]      (ファイル名は大文字8.3に変換)
LSX移植の tools/make_blank_disk.py と同じ形式。"""
import struct, sys, os
out, files = sys.argv[1], sys.argv[2:]
cyls, media, fatsz, mt = 80, 0xF9, 3, 0x10
tot = cyls * 2 * 9
img = bytearray(tot * 512)
bs = bytearray(512); bs[0:3] = b'\xEB\xFE\x90'; bs[3:11] = b'LD      '
bs[11:13] = struct.pack('<H', 512); bs[13] = 2; bs[14:16] = struct.pack('<H', 1); bs[16] = 2
bs[17:19] = struct.pack('<H', 112); bs[19:21] = struct.pack('<H', tot); bs[21] = media
bs[22:24] = struct.pack('<H', fatsz); bs[24:26] = struct.pack('<H', 9); bs[26:28] = struct.pack('<H', 2); bs[31] = 0xC9
img[:512] = bs
fat = bytearray(fatsz * 512); fat[0:3] = bytes([media, 0xFF, 0xFF])
def setfat(c, v):
    o = c * 3 // 2
    if c & 1: fat[o] = (fat[o] & 0x0F) | ((v << 4) & 0xF0); fat[o + 1] = (v >> 4) & 0xFF
    else: fat[o] = v & 0xFF; fat[o + 1] = (fat[o + 1] & 0xF0) | ((v >> 8) & 0x0F)
root0 = 1 + 2 * fatsz; rsec = 112 * 32 // 512; data0 = root0 + rsec
CL = 1024; nextc = 2; root = bytearray(rsec * 512)
for n, path in enumerate(files):
    d = open(path, 'rb').read()
    nm, _, ex = os.path.basename(path).upper().partition('.')
    ncl = max(1, (len(d) + CL - 1) // CL); first = nextc
    for i in range(ncl):
        c = nextc + i
        setfat(c, 0xFFF if i == ncl - 1 else c + 1)
        chunk = d[i * CL:(i + 1) * CL].ljust(CL, b'\0')
        o = (data0 + (c - 2) * 2) * 512; img[o:o + CL] = chunk
    nextc += ncl
    e = nm.ljust(8).encode() + ex.ljust(3).encode() + bytes([0x20]) + bytes(14) + struct.pack('<H', first) + struct.pack('<I', len(d))
    root[n * 32:n * 32 + 32] = e
for k in range(2): img[(1 + k * fatsz) * 512:(1 + k * fatsz + fatsz) * 512] = fat
img[root0 * 512:(root0 + rsec) * 512] = root
body = []; offs = []; pos = 0x2B0
for t in range(cyls * 2):
    c, h = divmod(t, 2); offs.append(pos); blk = b''
    for r in range(9):
        L = t * 9 + r; blk += struct.pack('<BBBBHBBB5xH', c, h, r + 1, 2, 9, 0, 0, 0, 512) + bytes(img[L * 512:(L + 1) * 512])
    body.append(blk); pos += len(blk)
offs += [0] * (164 - len(offs))
hdr = b'DATA'.ljust(17, b'\0') + bytes(9) + bytes([0, mt]) + struct.pack('<I', pos) + b''.join(struct.pack('<I', o) for o in offs)
open(out, 'wb').write(hdr + b''.join(body)); print('wrote', out, files)
