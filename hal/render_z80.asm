; render_z80.asm - row hash and control character filter for the screen diff (core/editor.c, built with -DR_ASM).
        section code_user
        public  _rowhash
        public  _rowfix
        public  _rowh2

; u16 rowhash(const u8 *row): h1 = sum of the 80 bytes (returned in HL), h2 = sum of the running h1 (stored in rowh2)
_rowhash:
        ld      hl,2
        add     hl,sp
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        ex      de,hl               ; HL = row
        ld      bc,0                ; h1
        ld      de,0                ; h2
        ld      a,80
        ld      (rhn),a
rh1:
        ld      a,(hl)
        inc     hl
        add     a,c
        ld      c,a
        jr      nc,rh2
        inc     b
rh2:
        ex      de,hl
        add     hl,bc
        ex      de,hl              ; h2 += h1
        ld      a,(rhn)
        dec     a
        ld      (rhn),a
        jr      nz,rh1
        ld      (_rowh2),de
        ld      h,b
        ld      l,c
        ret

; void rowfix(u8 *row, u8 n): bytes below 20h become blanks
_rowfix:
        ld      hl,2
        add     hl,sp
        ld      b,(hl)
        ld      a,b
        or      a
        ret     z
        ld      hl,4
        add     hl,sp
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        ex      de,hl
rf1:
        ld      a,(hl)
        cp      20h
        jr      nc,rf2
        ld      (hl),20h
rf2:
        inc     hl
        djnz    rf1
        ret

rhn:    defb    0
_rowh2: defw    0
