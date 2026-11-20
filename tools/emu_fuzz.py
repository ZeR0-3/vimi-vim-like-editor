#!/usr/bin/env python3
"""Random key-script fuzz: host core vs Z80 build in the emulator (finds Z80-only bugs such as hangs or miscompiles).
usage: emu_fuzz.py SEED COUNT > scenarios.txt   then   cd /tmp && python3 tools/emu_regress.py disk.d88 scenarios.txt"""
import random, sys
T = ['h','j','k','l','w','b','e','0','$','^','x','X','dd','dw','d$','D','yy','p','P','J','u','3j','2w','dG','dgg','yw','cwXY\\e',
     'ofoo\\e','Obar\\e','ihi\\e','Ahi\\e','.','>>','<<','G','gg','5G','vjd','Vjy','Vjd','vly','*','n','/a\\r','fa','ta',';',',','%',
     'gUiw','guu','g~~','ddp','xp','diw','daw','dap','yiw','3x','4dd','2p','ma','R12\\e','~','cc12\\e','S99\\e','s77\\e','C!\\e',
     ':s/a/Z/\\r',':%s/e/E/g\\r',':set nu\\r','+','-',' ','di(','ci"Q\\e','dab','di{','ya[','yi"','da"','dib','fq','f(','f{','f"','dG','d3j','y2k','"','>j','Vj>']
# (H L M zt zb depend on the rendered screen, which the host runner never draws, so they are left out)
T += ['}','{','2}','W','B','E','2E','3b','|','5|','2$','^','0','IA\\e','aB\\e','Oup\\e','R12\\e','rZ','X','3X','Y','2J','P','3P','``',"''",'mbG`b',"'a",'d`a',"y'a",'Tb','Fe','3l','9h','2-','2+','vey','vbd','v}d','#','N','2n','?e\\r','y}','c}Q\\e','d{','dB','cWx\\e','yE']
T = [t for t in T if t != '"']
rnd = random.Random(int(sys.argv[1]))
for _ in range(int(sys.argv[2])):
    print(''.join(rnd.choice(T) for _ in range(rnd.randint(4, 10))))
