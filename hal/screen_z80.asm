; screen_z80.asm - drawing the screen (the asm twin of core/ed_render.c; -DM_ASM)
;   ed_render : scroll so that the cursor is visible, build each row in rowc / rowa and send the ones that changed
;   lineno    : line number of a position (cached in lc_pos / lc_line)
; The screen is 24 text rows + a status row; sh_h1 / sh_h2 / sh_sig remember what each row shows (two checksums and an
; attribute signature), so that an unchanged row is not sent again.
    SECTION code_user
    PUBLIC _ed_render, _lineno, _putnum
    EXTERN ldcur, inc32, cmpm, subm, addm, ld32
    EXTERN _lstartc, _lend, _vis_range, _blkgeom
    EXTERN _tx_len, _tx_count, _tx_nthline, _tx_read, _rowhash, _rowfix, _rowh2, _hal_putrow, _hal_scroll
    EXTERN _cur, _top, _left, _mode, _nu, _vblk, _vline, _bc1, _bc2, _shvalid, _lc_pos, _lc_line
    EXTERN _rowc, _rowa, _sh_h1, _sh_h2, _sh_sig, _cmdch, _cmdlen, _cmdbuf, _mrc, _msg, _fname, _modified
    defc ROWS = 24
    defc COLS = 80

; DEHL = number of line breaks in [(HL), (DE))
cnt:
    push de
    call ld32
    pop bc
    push de
    push hl
    ld h,b
    ld l,c
    call ld32
    push de
    push hl
    ld hl,10
    push hl
    call _tx_count
    pop bc
    pop bc
    pop bc
    pop bc
    pop bc
    ret

; pos_t lineno(pos_t p) : 1-based number of the line holding p (counted from the last answer)
_lineno:
    ld hl,2
    add hl,sp
    call ld32
lnn:
    ld (ln_p),hl
    ld (ln_p+2),de
    ld hl,ln_p
    ld de,_lc_pos
    call cmpm
    jr nc,ln1
    ld hl,ln_p
    ld de,_lc_pos
    call cnt
    push de
    ex de,hl
    ld hl,(_lc_line)
    or a
    sbc hl,de
    ld (_lc_line),hl
    pop de
    ld hl,(_lc_line+2)
    sbc hl,de
    jr ln2
ln1:
    ld hl,_lc_pos
    ld de,ln_p
    call cnt
    push de
    ex de,hl
    ld hl,(_lc_line)
    add hl,de
    ld (_lc_line),hl
    pop de
    ld hl,(_lc_line+2)
    adc hl,de
ln2:
    ld (_lc_line+2),hl
    ld hl,(ln_p)
    ld (_lc_pos),hl
    ld hl,(ln_p+2)
    ld (_lc_pos+2),hl
    ld hl,(_lc_line)
    ld de,(_lc_line+2)
    ret

; DEHL in decimal at (pn_d), which moves on
pnum:
    ld (pn_v),hl
    ld (pn_v+2),de
    xor a
    ld (pn_nz),a
    ld a,10
    ld (pn_i),a
    ld hl,p10
pn1:
    ld c,'0'-1
pn2:
    inc c
    push hl
    ld de,pn_v
    ld b,4
    or a
pn3:
    ld a,(de)
    sbc a,(hl)
    ld (de),a
    inc hl
    inc de
    djnz pn3
    pop hl
    jr nc,pn2
    push hl                     ; one too many: add it back
    ld de,pn_v
    ld b,4
    or a
pn4:
    ld a,(de)
    adc a,(hl)
    ld (de),a
    inc hl
    inc de
    djnz pn4
    pop hl
    ld a,(pn_i)
    dec a
    jr z,pn5                    ; the last digit is always shown
    ld a,c
    cp '0'
    jr nz,pn5
    ld a,(pn_nz)
    or a
    jr z,pn6
pn5:
    ld a,1
    ld (pn_nz),a
    ld de,(pn_d)
    ld a,c
    ld (de),a
    inc de
    ld (pn_d),de
pn6:
    inc hl
    inc hl
    inc hl
    inc hl
    ld a,(pn_i)
    dec a
    ld (pn_i),a
    jr nz,pn1
    ret
p10:
    defw 0CA00h, 3B9Ah          ; 1000000000
    defw 0E100h, 05F5h          ; 100000000
    defw 9680h, 0098h           ; 10000000
    defw 4240h, 000Fh           ; 1000000
    defw 86A0h, 0001h           ; 100000
    defw 10000, 0
    defw 1000, 0
    defw 100, 0
    defw 10, 0
    defw 1, 0

; void putnum(u8 *dst, pos_t v, u8 *w) : v in decimal at dst, *w = the number of digits
_putnum:
    ld hl,8
    add hl,sp
    ld a,(hl)
    inc hl
    ld h,(hl)
    ld l,a
    ld (pn_d),hl
    push hl
    ld hl,6
    add hl,sp
    call ld32
    call pnum
    pop bc
    ld hl,2
    add hl,sp
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld hl,(pn_d)
    or a
    sbc hl,bc
    ld a,l
    ld (de),a
    ret

; copy the string at HL to DE (inside rowc)
puts:
    ld a,(hl)
    or a
    ret z
    ld (de),a
    inc hl
    inc de
    jr puts

; the status row -> rowc / rowa
bst:
    ld hl,_rowc
    ld de,_rowc+1
    ld (hl),' '
    ld bc,COLS-1
    ldir
    ld a,(_mode)
    cp 2
    jr nz,bs1
    ld a,(_cmdch)               ; the command line being typed
    ld (_rowc),a
    ld a,(_cmdlen)
    or a
    jr z,bs0
    ld c,a
    ld b,0
    ld hl,_cmdbuf
    ld de,_rowc+1
    ldir
bs0:
    ld a,42h
    jp bs_fill
bs1:
    ld hl,s_normal
    ld c,44h
    cp 1
    jr nz,bs2
    ld hl,s_insert
    ld c,46h
    jr bs3
bs2:
    cp 3
    jr nz,bs3
    ld c,42h
    ld hl,s_vblock
    ld a,(_vblk)
    or a
    jr nz,bs3
    ld hl,s_vline
    ld a,(_vline)
    or a
    jr nz,bs3
    ld hl,s_visual
bs3:
    ld a,c
    ld (bs_at),a
    ld de,_rowc
    call puts
    ld a,(_mrc)                 ; recording a macro: its register
    or a
    jr z,bs4
    ld (_rowc+12),a
bs4:
    ld hl,_msg
    ld a,(hl)
    or a
    jr nz,bs6
    ld hl,_fname
    ld a,(hl)
    or a
    jr nz,bs5
    ld hl,s_noname
bs5:
    ld de,_rowc+14
    call puts
    ld a,(_modified)
    or a
    jr z,bs7
    ld hl,s_plus
    ld de,_rowc+28
    call puts
    jr bs7
bs6:
    ld de,_rowc+14
    call puts
bs7:
    ld hl,_rowc+64              ; line,column
    ld (pn_d),hl
    call ldcur
    call lnn
    call pnum
    ld hl,(pn_d)
    ld (hl),','
    inc hl
    ld (pn_d),hl
    call _lstartc
    ld (ln_p),hl
    ld (ln_p+2),de
    ld hl,_cur
    ld de,ln_p
    call subm
    call inc32
    call pnum
    ld a,(bs_at)
bs_fill:
    ld hl,_rowa
    ld de,_rowa+1
    ld (hl),a
    ld bc,COLS-1
    ldir
    ret

; send row A (rowc / rowa, attribute signature C) unless the screen already shows it
flr:
    ld (fl_y),a
    ld a,c
    ld (fl_sig),a
    ld hl,_rowc
    push hl
    call _rowhash
    pop bc
    ld (fl_h1),hl
    ld a,(_shvalid)
    or a
    jr z,fl2
    ld a,(fl_sig)
    cp 0FDh
    jr z,fl2
    ld a,(fl_y)
    ld e,a
    ld d,0
    ld hl,_sh_sig
    add hl,de
    ld a,(fl_sig)
    cp (hl)
    jr nz,fl2
    ld hl,_sh_h1
    add hl,de
    add hl,de
    ld a,(fl_h1)
    cp (hl)
    jr nz,fl2
    inc hl
    ld a,(fl_h1+1)
    cp (hl)
    jr nz,fl2
    ld hl,_sh_h2
    add hl,de
    add hl,de
    ld a,(_rowh2)
    cp (hl)
    jr nz,fl2
    inc hl
    ld a,(_rowh2+1)
    cp (hl)
    ret z
fl2:
    ld a,(fl_y)
    ld e,a
    ld d,0
    ld hl,_sh_sig
    add hl,de
    ld a,(fl_sig)
    ld (hl),a
    ld hl,_sh_h1
    add hl,de
    add hl,de
    ld bc,(fl_h1)
    ld (hl),c
    inc hl
    ld (hl),b
    ld hl,_sh_h2
    add hl,de
    add hl,de
    ld bc,(_rowh2)
    ld (hl),c
    inc hl
    ld (hl),b
    push de
    ld hl,_rowc
    push hl
    ld hl,_rowa
    push hl
    call _hal_putrow
    pop bc
    pop bc
    pop bc
    ret

; the hardware scrolled A lines (signed, |A| < ROWS): move the remembered rows the same way
shs:
    ld (ss_n),a
    or a
    jp m,shn
    ld b,a
    ld a,ROWS+1
    sub b
    ld (ss_c),a
    ld hl,_sh_h1
    call up2
    ld hl,_sh_h2
    call up2
    ld hl,_sh_sig
    ld d,h
    ld e,l
    ld a,(ss_n)
    ld c,a
    ld b,0
    add hl,bc
    ld a,(ss_c)
    ld c,a
    ldir
    dec de                      ; the rows that came in at the bottom, and the status row: unknown
    ld a,(ss_n)
    inc a
    ld b,a
    ld a,0FEh
sh1:
    ld (de),a
    inc de
    djnz sh1
    ret
up2:
    ld d,h
    ld e,l
    ld a,(ss_n)
    add a,a
    ld c,a
    ld b,0
    add hl,bc
    ld a,(ss_c)
    add a,a
    ld c,a
    ldir
    ret
shn:
    neg
    ld (ss_n),a
    ld b,a
    ld a,ROWS+1
    sub b
    ld (ss_c),a
    ld hl,_sh_h1
    call dn2
    ld hl,_sh_h2
    call dn2
    ld hl,_sh_sig+ROWS
    ld d,h
    ld e,l
    ld a,(ss_n)
    ld c,a
    ld b,0
    or a
    sbc hl,bc
    ld a,(ss_c)
    ld c,a
    lddr
    ld hl,_sh_sig
    ld a,(ss_n)
    ld b,a
    ld a,0FEh
sh2:
    ld (hl),a
    inc hl
    djnz sh2
    ld (_sh_sig+ROWS),a
    ret
dn2:
    ld de,ROWS*2+1
    add hl,de
    ld d,h
    ld e,l
    ld a,(ss_n)
    add a,a
    ld c,a
    ld b,0
    or a
    sbc hl,bc
    ld a,(ss_c)
    add a,a
    ld c,a
    lddr
    ret

; HL = HL / 10, A = the remainder.  Keeps BC, DE.
div10:
    push bc
    ld b,16
    xor a
dv1:
    add hl,hl
    rla
    cp 10
    jr c,dv2
    sub 10
    inc l
dv2:
    djnz dv1
    pop bc
    ret
; HL -> the first text column of rowc (after the line number gutter)
rowp:
    ld hl,_rowc
    ld a,(r_nw)
    ld e,a
    ld d,0
    add hl,de
    ret

; void ed_render(void)
_ed_render:
    xor a
    ld (r_nw),a
    ld (r_scr),a
    ld hl,COLS
    ld a,(_nu)
    or a
    jr z,r1
    ld a,5
    ld (r_nw),a
    ld l,COLS-5
r1:
    ld (r_tw),hl
    call _lstartc
    ld (r_curs),hl
    ld (r_curs+2),de
    ld hl,_top
    ld de,r_old
    ld bc,4
    ldir
    ld hl,r_curs                ; the cursor is above the screen: scroll up
    ld de,_top
    call cmpm
    jr nc,r3
    ld hl,r_curs
    ld de,_top
    ld bc,4
    ldir
    call _tx_len
    ld (r_len),hl
    ld (r_len+2),de
    ld hl,r_len
    ld de,r_old
    call cmpm
    jr nc,r2
    ld hl,r_len                 ; (the text may have shrunk below the old top)
    ld de,r_old
    ld bc,4
    ldir
r2:
    ld hl,_top
    ld de,r_old
    call cnt
    ld a,d
    or e
    or h
    jr nz,r2a
    ld a,l
    cp ROWS
    jr c,r2b
r2a:
    ld a,ROWS
r2b:
    neg
    ld (r_scr),a
r3:
    ld hl,_top                  ; the cursor is below the screen: scroll down
    ld de,r_curs
    call cnt
    ld (r_rel),hl
    ld a,d
    or e
    or h
    jr nz,r4
    ld a,l
    cp ROWS
    jr c,r5
    cp ROWS+17
    jr nc,r4
r3a:
    ld hl,(_top)
    ld de,(_top+2)
    call _lend
    call inc32
    ld (_top),hl
    ld (_top+2),de
    ld a,(r_scr)
    cp ROWS
    jr nc,r3b
    inc a
    ld (r_scr),a
r3b:
    ld hl,r_rel
    dec (hl)
    ld a,(hl)
    cp ROWS
    jr nc,r3a
    jr r5
r4:
    ld hl,(r_curs)              ; a far jump: find the top line by number
    ld de,(r_curs+2)
    call lnn
    ld bc,ROWS-1
    or a
    sbc hl,bc
    jr nc,r4a
    dec de
r4a:
    push de
    push hl
    call _tx_nthline
    pop bc
    pop bc
    ld (_top),hl
    ld (_top+2),de
    ld a,ROWS
    ld (r_scr),a
r5:
    ld hl,(_cur)                ; sideways
    ld de,(r_curs)
    or a
    sbc hl,de
    ld (r_cc),hl
    ld de,(_left)
    or a
    sbc hl,de
    add hl,de
    jr nc,r6
    ld (_left),hl
r6:
    ld hl,(_left)
    ld de,(r_tw)
    add hl,de
    ex de,hl
    ld hl,(r_cc)
    or a
    sbc hl,de
    jr c,r7
    ld hl,(r_cc)
    ld de,(r_tw)
    or a
    sbc hl,de
    inc hl
    ld (_left),hl
r7:
    ld a,(_shvalid)             ; a small vertical move: hardware scroll
    or a
    jr z,r9
    ld a,(r_scr)
    or a
    jr z,r9
    cp ROWS
    jr z,r8
    cp -ROWS
    jr z,r8
    ld l,a
    rla
    sbc a,a
    ld h,a
    push hl
    call _hal_scroll
    pop bc
    ld a,(r_scr)
    call shs
    jr r9
r8:
    xor a
    ld (_shvalid),a
r9:
    ld hl,_top
    ld de,r_s
    ld bc,4
    ldir
    call _tx_len
    ld (r_len),hl
    ld (r_len+2),de
    ld hl,0
    ld (r_vs),hl
    ld (r_vs+2),hl
    ld (r_ve),hl
    ld (r_ve+2),hl
    ld a,(_mode)
    cp 3
    jr nz,r10
    ld hl,r_vs
    push hl
    ld hl,r_ve
    push hl
    call _vis_range
    pop bc
    pop bc
    ld a,(_vblk)
    or a
    call nz,_blkgeom
r10:
    ld a,(_nu)
    or a
    jr z,r11
    ld hl,(_top)
    ld de,(_top+2)
    call lnn
    ld (r_ln),hl
r11:
    xor a
    ld (r_y),a
rl:                             ; ---- one text row
    ld hl,_rowc
    ld de,_rowc+1
    ld (hl),' '
    ld bc,COLS-1
    ldir
    ld hl,_rowa
    ld de,_rowa+1
    ld (hl),7
    ld bc,COLS-1
    ldir
    ld a,0FFh
    ld (r_sig),a
    ld hl,r_s
    ld de,r_len
    call cmpm
    jr c,rl1
    ld a,'~'                    ; past the end of the text
    ld (_rowc),a
    jp rl9
rl1:
    ld hl,(r_s)
    ld de,(r_s+2)
    call _lend
    ld (r_e),hl
    ld (r_e+2),de
    ld hl,(_left)
    ld de,r_s
    call addm
    ld (r_k),hl
    ld (r_k+2),de
    ld hl,r_k
    ld de,r_e
    call cmpm
    jr nc,rl3
    ld hl,r_e                   ; the visible part of the line
    ld de,r_k
    call subm
    ld a,d
    or e
    jr nz,rl2
    ld bc,(r_tw)
    sbc hl,bc
    add hl,bc
    jr c,rl2a
rl2:
    ld hl,(r_tw)
rl2a:
    ld (r_x),hl
    call rowp
    push hl
    ld hl,(r_k+2)
    push hl
    ld hl,(r_k)
    push hl
    ld hl,0
    push hl
    ld hl,(r_x)
    push hl
    call _tx_read
    pop bc
    pop bc
    pop bc
    pop bc
    pop bc
    call rowp
    push hl
    ld hl,(r_x)
    push hl
    call _rowfix
    pop bc
    pop bc
rl3:
    ld hl,r_s                   ; the cursor
    ld de,r_curs
    call cmpm
    jr nz,rl4
    ld hl,(r_cc)
    ld de,(_left)
    or a
    sbc hl,de
    ld de,(r_tw)
    or a
    sbc hl,de
    add hl,de
    jr nc,rl4
    ld a,l
    ld (r_sig),a
    call rvat
rl4:
    ld hl,r_vs                  ; the visual selection (offsets within the line)
    ld de,r_ve
    call cmpm
    jp nc,rl7
    ld hl,r_s
    ld de,r_ve
    call cmpm
    jp nc,rl7
    ld hl,r_vs
    ld de,r_s
    call subm
    jr nc,rl4a
    ld hl,0
rl4a:
    ld (r_a),hl
    ld hl,r_e
    ld de,r_s
    call subm
    ld (r_x),hl                 ; length of the line
    inc hl
    ld (r_b),hl
    ld hl,(r_e)
    ld de,(r_e+2)
    call inc32
    ld (r_k),hl
    ld (r_k+2),de
    ld hl,r_ve
    ld de,r_k
    call cmpm
    jr nc,rl5
    ld hl,r_ve
    ld de,r_s
    call subm
    ld (r_b),hl
rl5:
    ld a,(_vblk)
    or a
    jr z,rl6
    ld hl,(_bc1)                ; a block: its columns on every row
    ld (r_a),hl
    ld hl,(r_x)
    ld de,(_bc2)
    inc de
    or a
    sbc hl,de
    add hl,de
    jr c,rl5a
    ex de,hl
rl5a:
    ld (r_b),hl
rl6:
    ld hl,(r_a)
    ld de,(r_b)
    or a
    sbc hl,de
    jr nc,rl7
    ld hl,(r_a)
    ld de,(_left)
    or a
    sbc hl,de
    jr c,rl6a
    ld de,(r_tw)
    or a
    sbc hl,de
    add hl,de
    jr nc,rl6a
    call rvat
    ld a,0FDh
    ld (r_sig),a
rl6a:
    ld hl,(r_a)
    inc hl
    ld (r_a),hl
    jr rl6
rl7:
    ld a,(_nu)                  ; the line number: 4 digits and a blank
    or a
    jr z,rl8
    ld hl,(r_ln)
    push hl
    inc hl
    ld (r_ln),hl
    pop hl
    ld de,_rowc+3
    ld b,4
rl7a:
    call div10
    add a,'0'
    ld (de),a
    dec de
    ld a,h
    or l
    jr z,rl8
    djnz rl7a
rl8:
    ld hl,(r_e)
    ld de,(r_e+2)
    call inc32
    ld (r_s),hl
    ld (r_s+2),de
rl9:
    ld a,(r_sig)
    ld c,a
    ld a,(r_y)
    call flr
    ld hl,r_y
    inc (hl)
    ld a,(hl)
    cp ROWS
    jp c,rl
    call bst
    ld a,(_rowa)
    ld c,a
    ld a,ROWS
    call flr
    ld a,1
    ld (_shvalid),a
    ret
; text column L (0-based, on the screen) of this row in reverse video
rvat:
    ld a,(r_nw)
    add a,l
    ld e,a
    ld d,0
    ld hl,_rowa
    add hl,de
    ld (hl),47h
    ret

s_normal: defm "NORMAL"
    defb 0
s_insert: defm "-- INSERT --"
    defb 0
s_visual: defm "-- VISUAL --"
    defb 0
s_vline: defm "-- V-LINE --"
    defb 0
s_vblock: defm "-- V-BLOCK --"
    defb 0
s_noname: defm "[No Name]"
    defb 0
s_plus: defm "[+]"
    defb 0

    SECTION bss_user
ln_p:   defs 4
pn_v:   defs 4
pn_d:   defs 2
pn_i:   defb 0
pn_nz:  defb 0
bs_at:  defb 0
fl_y:   defb 0
fl_sig: defb 0
fl_h1:  defs 2
ss_n:   defb 0
ss_c:   defb 0
r_nw:   defb 0
r_scr:  defb 0
r_y:    defb 0
r_sig:  defb 0
r_tw:   defs 2
r_cc:   defs 2
r_ln:   defs 2
r_rel:  defs 2
r_x:    defs 2
r_a:    defs 2
r_b:    defs 2
r_curs: defs 4
r_old:  defs 4
r_len:  defs 4
r_s:    defs 4
r_e:    defs 4
r_k:    defs 4
r_vs:   defs 4
r_ve:   defs 4
