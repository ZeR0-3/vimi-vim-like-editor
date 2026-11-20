#!/usr/bin/env python3
"""Compare the Z80 build (in the emulator) with the host build of the same editor core.
usage: tools/emu_regress.py disk.d88 [scenario-file]
scenario: one key script per line (\\e = Esc, \\r = Return, \\v = Ctrl-V, \\^d = Ctrl-D ...); lines starting with # are ignored.
Needs: ./mz2500w-cli in /home/claude/emu, the LSX boot disk, /tmp/C.TXT (any text file named C.TXT on the disk)."""
import subprocess, sys, os, re, tempfile, shutil
EMU = '/home/claude/emu'
LSX = '/home/claude/lsx/lsx-dodgers-mz2500/dist/LSX2500_80col.d88'
CAT = '/home/claude/lsx/lsx-dodgers-mz2500/tools/d88_cat.py'
HOSTRUN = '/tmp/hostrun'
# another file / options: MZV_FILE=BIG.TXT MZV_ARGS='-sF120 ' MZV_T0=2600 MZV_TAIL=9000 (frames before the first key / after :wq)
FILE = os.environ.get('MZV_FILE', 'C.TXT'); VARGS = os.environ.get('MZV_ARGS', '')
T0 = int(os.environ.get('MZV_T0', '900')); TAIL = int(os.environ.get('MZV_TAIL', '1000'))
disk = sys.argv[1]
scen = open(sys.argv[2]).read().splitlines() if len(sys.argv) > 2 else [
    r'2w2x', r'3Dp', r'wwD', r'jddP', r'jmajjd\'a', r'jyy3p', r'ciwNEW\e', r'wgUiw', r'gUU', r'jvlU', r'jVjd', r'3J', r'RXYZ\e',
    r':s/a.p/Q/\r', r':%s/alpha/A/g\r', r':%s/[a-c]*/<&>/g\r', r'/gamma\rnnN', r'}x', r'jj{', r'd}', r'3~', r'ma$`ax', r'Gdgg', r'ddu', r'ddu\x12'.replace(r'\x12', ''),
    r'ifoo\e..', r'3ihi \e', r':set ic\r:s/ALPHA/x/\r', r'jjwdw.', r'>>j.', r'ggVG>', r'*', r'fa;;x', r'ta,x', r'dfg', r'%',
]
SPECIAL = {'{': 'lbracket', '}': 'rbracket', '~': 'caret', '`': 'at', '|': 'yen', '"': '2'}   # typed as Shift + key (not reachable with --type)
def esc_split(s):
    # split into typeable chunks and Esc/Return events
    out, cur = [], ''
    i = 0
    while i < len(s):
        if s.startswith(r'\e', i):
            if cur: out.append(('t', cur)); cur = ''
            out.append(('e', None)); i += 2
        elif s.startswith(r'\v', i):
            if cur: out.append(('t', cur)); cur = ''
            out.append(('v', None)); i += 2
        elif s.startswith('\\^', i) and i + 2 < len(s):
            if cur: out.append(('t', cur)); cur = ''
            out.append(('c', s[i + 2])); i += 3
        elif s[i] in SPECIAL:
            if cur: out.append(('t', cur)); cur = ''
            out.append(('s', SPECIAL[s[i]])); i += 1
        elif s.startswith(r'\r', i): cur += '\r'; i += 2
        elif s.startswith('\\\\', i): cur += '\\'; i += 2
        else: cur += s[i]; i += 1
    if cur: out.append(('t', cur))
    return out
def emu_run(script):
    args = ['--type', 'B:\\r:450', '--type', f'VIMI {VARGS}{FILE}\\r:520']
    t = T0
    for kind, v in esc_split(script):
        if kind == 'e': args += ['--key-pulse', f'esc:{t}:8']; t += 120
        elif kind == 'v': args += ['--key-pulse', f'ctrl:{t}:30', '--key-pulse', f'v:{t+4}:10']; t += 80
        elif kind == 'c': args += ['--key-pulse', f'ctrl:{t}:30', '--key-pulse', f'{v}:{t+4}:10']; t += 80
        elif kind == 's': args += ['--key-pulse', f'shift:{t}:30', '--key-pulse', f'{v}:{t+4}:10']; t += 80
        else:
            args += ['--type', v.replace('\r', '\\r') + f':{t}']; t += 60 + 28 * len(v)
    args += ['--type', f':wq\\r:{t+150}']
    work = tempfile.mkdtemp(); d = os.path.join(work, 'r.d88'); shutil.copy(disk, d); outp = os.path.join(work, 'o.d88')
    subprocess.run(['./mz2500w-cli', '--rom-dir', 'roms', '--disk-a', LSX, '--disk-b', d, '--frames', str(t + TAIL)] + args + ['--disk-save', '1:' + outp],
                   cwd=EMU, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=118 if TAIL <= 1000 else 600)
    if not os.path.exists(outp): return None
    r = subprocess.run(['python3', CAT, outp, FILE], capture_output=True)
    shutil.rmtree(work)
    return r.stdout.replace(b'\r', b'').split(b'\x1a')[0]
def emu_shot(script, dsk):       # the screen after the keys (no :wq): (pixels of the final frame, text lines)
    args = ['--type', 'B:\\r:450', '--type', f'VIMI {VARGS}{FILE}\\r:520']
    t = T0
    for kind, v in esc_split(script):
        if kind == 'e': args += ['--key-pulse', f'esc:{t}:8']; t += 120
        elif kind == 'v': args += ['--key-pulse', f'ctrl:{t}:30', '--key-pulse', f'v:{t+4}:10']; t += 80
        elif kind == 'c': args += ['--key-pulse', f'ctrl:{t}:30', '--key-pulse', f'{v}:{t+4}:10']; t += 80
        elif kind == 's': args += ['--key-pulse', f'shift:{t}:30', '--key-pulse', f'{v}:{t+4}:10']; t += 80
        else:
            args += ['--type', v.replace('\r', '\\r') + f':{t}']; t += 60 + 28 * len(v)
    work = tempfile.mkdtemp(); d = os.path.join(work, 'r.d88'); shutil.copy(dsk, d); shot = os.path.join(work, 's.ppm')
    r = subprocess.run(['./mz2500w-cli', '--rom-dir', 'roms', '--disk-a', LSX, '--disk-b', d, '--frames', str(t + 400)] + args + ['--screenshot', shot, '--screen-report'],
                       cwd=EMU, capture_output=True, timeout=300)
    px = open(shot, 'rb').read() if os.path.exists(shot) else b''
    shutil.rmtree(work)
    return px, [l for l in r.stdout.decode('latin1').split('\n') if l.startswith('screen:')]
REF = os.environ.get('MZV_REF')    # MZV_REF=old.d88: compare the SCREEN (pixels: text, colours, reverse) of the disk with that of old.d88
if REF:
    bad = 0
    for s in scen:
        if not s or s.startswith('#'): continue
        a, ta = emu_shot(s, REF); b, tb = emu_shot(s, disk)
        ok = a and a == b
        print(('ok   ' if ok else 'DIFF ') + s)
        if not ok:
            bad += 1
            for i in range(max(len(ta), len(tb))):
                x = ta[i] if i < len(ta) else '<none>'; y = tb[i] if i < len(tb) else '<none>'
                if x != y: print('   row', i, 'ref:', x[8:78].rstrip()); print('   row', i, 'new:', y[8:78].rstrip()); break
            else: print('   (same text: colours or reverse differ)')
    print('FAILED' if bad else 'ALL OK', bad)
    sys.exit(1 if bad else 0)
bad = 0
for s in scen:
    if not s or s.startswith('#'): continue
    s2 = s + r'\e'              # always end in normal mode, or the closing :wq would be typed into the text
    h = subprocess.run([HOSTRUN, '/tmp/' + FILE, s2], capture_output=True).stdout
    e = emu_run(s2)
    ok = e is not None and e.rstrip(b'\n') == h.rstrip(b'\n')
    print(('ok   ' if ok else 'DIFF ') + s)
    if not ok and os.environ.get("MZV_DUMP"): open("/tmp/emu_out.txt","wb").write(e or b""); open("/tmp/host_out.txt","wb").write(h)
    if not ok:
        bad += 1
        hl, el = h.split(b'\n'), (e or b'').split(b'\n')
        for i in range(max(len(hl), len(el))):
            a = hl[i] if i < len(hl) else b'<none>'; b = el[i] if i < len(el) else b'<none>'
            if a != b: print('   line', i + 1, 'host:', a[:60], 'emu:', b[:60]); break
print('FAILED' if bad else 'ALL OK', bad)
sys.exit(1 if bad else 0)
