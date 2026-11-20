; regex_z80.asm - the :s and / matcher (atom_end, atom_match, mhere of editor.c) in Z80.
;   syntax: c . [set] [^set] [a-z] x* \c ^(start only, handled by the caller) $(end only)
;   u16 mhere(u8 *re, u16 t): match re at offset t of the current line (text at rxb, length rxe);
;   returns the end offset of the match, or 0FFFFh.
    SECTION code_user
    PUBLIC _mhere, _rx_scan
    EXTERN _tx_get, _tx_len, _tx_find, _rxb, _rxe, _icase, _rxpat, _rxanch, _rxlit

; ae: HL = atom -> HL = end of the atom (keeps DE; clobbers A, BC)
ae:
    ld a,(hl)
    cp '\\'
    jr nz,ae1
    inc hl
    ld a,(hl)
    or a
    ret z                      ; a lone trailing backslash is a one character atom
    inc hl
    ret
ae1:
    cp '['
    jr nz,ae_one
    ld b,h
    ld c,l
    inc hl
    ld a,(hl)
    cp '^'
    jr nz,ae2
    inc hl
ae2:
    ld a,(hl)
    cp ']'
    jr nz,ae3
    inc hl
ae3:
    ld a,(hl)
    or a
    jr z,ae_nok
    cp ']'
    jr z,ae_ok
    inc hl
    jr ae3
ae_ok:
    inc hl
    ret
ae_nok:
    ld h,b
    ld l,c
ae_one:
    inc hl
    ret

; fold: A = character -> lower case when :set ignorecase (keeps everything else)
fold:
    cp 'A'
    ret c
    cp 'Z'+1
    ret nc
    push bc
    ld b,a
    ld a,(_icase)
    or a
    ld a,b
    pop bc
    ret z
    add a,20h
    ret

; cph: compare the (folded) text character rx_c with the (folded) pattern byte (HL): flags as CP (HL); clobbers B
cph:
    ld a,(hl)
    call fold
    ld b,a
    ld a,(rx_c)
    cp b
    ret

; am: HL = atom, A = character -> A = 1 if the atom matches it, else 0 (clobbers BC, DE, HL)
am:
    call fold
    ld (rx_c),a
    ld a,(hl)
    cp '.'
    jr z,am_t
    cp '\\'
    jr nz,am1
    inc hl
    ld a,(hl)
    dec hl
    or a
    jr z,am1
    inc hl
    call cph
    jr z,am_t
    jr am_f
am1:
    ld a,(hl)
    cp '['
    jr nz,am_lit
    push hl
    call ae
    pop de
    inc de
    or a
    sbc hl,de                  ; end == atom + 1 : not a set
    dec de
    ex de,hl
    jr z,am_lit
    inc hl                     ; p
    ld c,0                     ; neg
    ld a,(hl)
    cp '^'
    jr nz,am_s1
    inc hl
    inc c
am_s1:
    ld d,0                     ; ok
am_lp:
    inc hl
    ld a,(hl)
    dec hl
    cp '-'
    jr nz,am_s2
    inc hl
    inc hl
    ld a,(hl)
    dec hl
    dec hl
    or a
    jr z,am_s2
    cp ']'
    jr z,am_s2
    call cph                   ; range p[0]-p[2]
    jr c,am_r1
    inc hl
    inc hl
    ld a,(hl)
    call fold
    ld e,a
    dec hl
    dec hl
    ld a,(rx_c)
    cp e
    jr z,am_in
    jr nc,am_r1
am_in:
    ld d,1
am_r1:
    inc hl
    inc hl
    inc hl
    jr am_nx
am_s2:
    call cph
    jr nz,am_s3
    ld d,1
am_s3:
    inc hl
am_nx:
    ld a,(hl)
    or a
    jr z,am_end
    cp ']'
    jr nz,am_lp
am_end:
    ld a,d
    xor c
    ret
am_lit:
    call cph
    jr z,am_t
am_f:
    xor a
    ret
am_t:
    ld a,1
    ret

; tch: DE = offset in the line -> A = text byte at rxb + DE (clobbers everything but the stack)
tch:
    ld hl,(_rxb)
    add hl,de
    ld bc,(_rxb+2)
    jr nc,tc1
    inc bc
tc1:
    push bc
    push hl
    call _tx_get
    pop af
    pop af
    ld a,l
    ret

_mhere:
    ld hl,2
    add hl,sp
    ld e,(hl)
    inc hl
    ld d,(hl)                  ; t
    inc hl
    ld c,(hl)
    inc hl
    ld b,(hl)
    ld h,b
    ld l,c                     ; re

; mh: HL = re, DE = t -> HL = end offset or 0FFFFh.  Frame: (ix+0) t, (ix+2) re, (ix+4) old ix, (ix-2) nx, (ix-4) p
mh:
    push ix
    push hl
    push de
    ld ix,0
    add ix,sp
    push hl
    push hl
mh_loop:
    ld l,(ix+2)
    ld h,(ix+3)
    ld a,(hl)
    or a
    jp z,mh_rt
    cp '$'
    jr nz,mh2
    inc hl
    ld a,(hl)
    or a
    jr nz,mh2
    ld e,(ix+0)
    ld d,(ix+1)
    ld hl,(_rxe)
    or a
    sbc hl,de
    jp z,mh_rt
    jp mh_none
mh2:
    ld l,(ix+2)
    ld h,(ix+3)
    call ae
    ld (ix-2),l
    ld (ix-1),h
    ld a,(hl)
    cp '*'
    jr z,mh_star
    ld e,(ix+0)                ; one atom: needs t < rxe and a match
    ld d,(ix+1)
    ld hl,(_rxe)
    or a
    sbc hl,de
    jp z,mh_none
    jp c,mh_none
    call tch
    ld l,(ix+2)
    ld h,(ix+3)
    call am
    or a
    jp z,mh_none
    ld l,(ix+0)
    ld h,(ix+1)
    inc hl
    ld (ix+0),l
    ld (ix+1),h
    ld a,(ix-2)
    ld (ix+2),a
    ld a,(ix-1)
    ld (ix+3),a
    jr mh_loop
mh_star:
    ld a,(ix+0)                ; p = t
    ld (ix-4),a
    ld a,(ix+1)
    ld (ix-3),a
ms_l:
    ld e,(ix-4)
    ld d,(ix-3)
    ld hl,(_rxe)
    or a
    sbc hl,de
    jr z,ms_d
    jr c,ms_d
    call tch
    ld l,(ix+2)
    ld h,(ix+3)
    call am
    or a
    jr z,ms_d
    ld l,(ix-4)
    ld h,(ix-3)
    inc hl
    ld (ix-4),l
    ld (ix-3),h
    jr ms_l
ms_d:
    ld l,(ix-2)                ; q = mhere(nx + 1, p); if (q != NONE || p == t) return q; p--;
    ld h,(ix-1)
    inc hl
    ld e,(ix-4)
    ld d,(ix-3)
    call mh
    ld a,h
    and l
    inc a
    jp nz,mh_ret
    ld e,(ix-4)
    ld d,(ix-3)
    ld l,(ix+0)
    ld h,(ix+1)
    or a
    sbc hl,de
    jp z,mh_none
    ld l,(ix-4)
    ld h,(ix-3)
    dec hl
    ld (ix-4),l
    ld (ix-3),h
    jr ms_d
mh_rt:
    ld l,(ix+0)
    ld h,(ix+1)
    jr mh_ret
mh_none:
    ld hl,0FFFFh
mh_ret:
    ld sp,ix
    pop de
    pop de
    pop ix
    ret


; DE:HL = rxb + HL
rb_add:
    ld de,(_rxb)
    add hl,de
    ld de,(_rxb+2)
    ret nc
    inc de
    ret

; u16 rx_scan(pos_t ls, u16 lo, u16 hi, u8 back)  -- first (or last) match start in [lo,hi] of the line at ls, else 0FFFFh
;   sets rxb/rxe; honours rxpat / rxanch / rxlit
_rx_scan:
    push ix
    ld ix,0
    add ix,sp                  ; +4 back, +6 hi, +8 lo, +10 ls lo, +12 ls hi
    ld l,(ix+10)
    ld h,(ix+11)
    ld (_rxb),hl
    ld e,(ix+12)
    ld d,(ix+13)
    ld (_rxb+2),de
    push de
    push hl
    call _tx_len
    push de
    push hl
    ld hl,10
    push hl
    call _tx_find              ; end of the line
    pop af
    pop af
    pop af
    pop af
    pop af
    ld e,(ix+10)
    ld d,(ix+11)
    or a
    sbc hl,de
    ld (_rxe),hl               ; rxe = line length
    ld e,(ix+6)
    ld d,(ix+7)                ; hi
    or a
    sbc hl,de
    jr nc,rs1                  ; rxe >= hi
    ld hl,(_rxe)
    ld (ix+6),l
    ld (ix+7),h
rs1:
    ld l,(ix+6)
    ld h,(ix+7)
    ld e,(ix+8)
    ld d,(ix+9)
    or a
    sbc hl,de                  ; hi - lo
    jp c,rs_none
    ld a,(_rxanch)
    or a
    jr z,rs_na
    ld a,(ix+8)
    or (ix+9)
    jp nz,rs_none
    ld hl,(_rxpat)
    ld de,0
    call mh
    ld a,h
    and l
    inc a
    jp z,rs_none
    ld hl,0
    jp rs_ret
rs_na:
    ld a,(ix+4)
    or a
    jr nz,rs_back
    ld l,(ix+8)
    ld h,(ix+9)                ; t = lo
rs_f:
    ld e,(ix+6)
    ld d,(ix+7)
    push hl
    ex de,hl
    or a
    sbc hl,de                  ; hi - t
    pop hl
    jp c,rs_none
    ld a,(_rxlit)
    or a
    jr z,rs_m
    call rb_add                ; q = tx_find(rxb + t, rxb + rxe, rxlit)
    push de
    push hl
    ld hl,(_rxe)
    call rb_add
    push de
    push hl
    ld a,(_rxlit)
    ld l,a
    ld h,0
    push hl
    call _tx_find
    pop af
    pop af
    pop af
    pop af
    pop af
    ld de,(_rxb)
    or a
    sbc hl,de                  ; t = q - rxb
    ld e,(ix+6)
    ld d,(ix+7)
    push hl
    ex de,hl
    or a
    sbc hl,de
    pop hl
    jp c,rs_none               ; t > hi
    ld de,(_rxe)
    push hl
    or a
    sbc hl,de
    pop hl
    jp nc,rs_none              ; t >= rxe
rs_m:
    ld (rs_t),hl
    ex de,hl
    ld hl,(_rxpat)
    call mh
    ld a,h
    and l
    inc a
    jr nz,rs_ok
    ld hl,(rs_t)
    inc hl
    jr rs_f
rs_ok:
    ld hl,(rs_t)
    jr rs_ret
rs_back:
    ld l,(ix+6)
    ld h,(ix+7)                ; t = hi
rs_b:
    ld (rs_t),hl
    ex de,hl
    ld hl,(_rxpat)
    call mh
    ld a,h
    and l
    inc a
    jr nz,rs_ok
    ld hl,(rs_t)
    ld e,(ix+8)
    ld d,(ix+9)
    or a
    sbc hl,de
    jr z,rs_none
    ld hl,(rs_t)
    dec hl
    jr rs_b
rs_none:
    ld hl,0FFFFh
rs_ret:
    pop ix
    ret

    SECTION bss_user
rx_c:   defb 0
rs_t:   defw 0
