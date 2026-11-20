; pal.asm - "iceberg"-style palette for the MZ-1M10 4096-colour board (see palette.md).  LSX only (C=6Fh -> L=4).
; Text colour numbers are GRB (1 B, 2 R, 3 R+B, 4 G, 5 G+B, 6 G+R, 7 all); entries n and n+8 get the same colour.
; Editor uses: 7 = text, 4 = status NORMAL, 6 = INSERT, 2 = COMMAND (status bars are reverse video).
        section code_user
        public  _pal_on
        public  _pal_off
        public  _pal_enable
_pal_on:
        ld      a,(_pal_enable)
        or      a
        ret     z
        ld      c,6Fh
        call    5
        ld      a,l
        cp      4
        ret     nz
        ld      hl,paltab
        ld      d,1
pl:     ld      a,d
        add     a,a
        ld      b,a
        call    wr
        ld      a,d
        add     a,8
        add     a,a
        ld      b,a
        call    wr
        inc     hl
        inc     hl
        inc     d
        ld      a,d
        cp      8
        jr      nz,pl
        ld      bc,0FB00h           ; AND FBh, OR 00h : bit2 = 0 -> board palette on
        jr      opn_mod
_pal_off:
        ld      a,(_pal_enable)
        or      a
        ret     z
        ld      c,6Fh
        call    5
        ld      a,l
        cp      4
        ret     nz
        ld      bc,0FF04h           ; bit2 = 1 -> digital 8 colours
opn_mod:                            ; B = AND mask, C = OR mask on OPN register 0Eh
        di
        call    ow
        ld      a,0Eh
        out     (0C8h),a
        call    ow
        in      a,(0C9h)
        and     b
        or      c
        ld      e,a
        call    ow
        ld      a,0Eh
        out     (0C8h),a
        call    ow
        ld      a,e
        out     (0C9h),a
        ei
        ret
ow:     in      a,(0C8h)
        rlca
        jr      c,ow
        ret
wr:     ld      c,0AEh              ; B = entry*2 (+1 for green)
        ld      a,(hl)
        out     (c),a
        inc     b
        inc     hl
        ld      a,(hl)
        out     (c),a
        dec     hl
        ret
; per entry: (R<<4)|B , G      (iceberg: fg c6c8d1, blue 84a0c6, cyan 89b8c2, green b4be82, orange e2a478, purple a093c7, gray 6b7089)
paltab:
        defb 068h,06h            ; 1: 6b7089
        defb 0D7h,09h            ; 2: e2a478
        defb 09Bh,08h            ; 3: a093c7
        defb 07Bh,09h            ; 4: 84a0c6
        defb 08Bh,0Ah            ; 5: 89b8c2
        defb 0A7h,0Bh            ; 6: b4be82
        defb 0BCh,0Bh            ; 7: c6c8d1
_pal_enable: defb 1
