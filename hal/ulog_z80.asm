; ulog_z80.asm - undo-log helper: drop the oldest group's entries by sliding the log arrays down
; void ulog_shift(u8 L, u8 k, u16 cut)   (sccz80: args pushed left to right, caller pops)
;   for each array: entries [k..n) of log L move to [0..n-k); u_off[] additionally gets 'cut' subtracted.
; Arrays are laid out as [2][24] (UE=24): typ/grp 1 byte, len/off 2 bytes, pos 4 bytes per entry.
    SECTION code_user
    PUBLIC _ulog_shift
    EXTERN _u_typ, _u_pos, _u_len, _u_off, _u_grp, _u_n

_ulog_shift:
    ld hl,2
    add hl,sp
    ld e,(hl)
    inc hl
    ld d,(hl)          ; de = cut
    inc hl
    ld c,(hl)          ; c = k
    inc hl
    inc hl
    ld a,(hl)          ; a = L
    ld (ul_cut),de
    ld h,0
    ld l,a
    ld de,_u_n
    add hl,de
    ld a,(hl)          ; a = u_n[L]
    sub c
    ret z
    ld (ul_cnt),a
    ld a,c
    ld (ul_k),a
    ; L*24 : recompute from L
    ld hl,2
    add hl,sp
    inc hl
    inc hl
    inc hl
    inc hl             ; sp+6 = L
    ld a,(hl)
    ld h,0
    ld l,a
    add hl,hl
    ld d,h
    ld e,l
    add hl,hl          ; L*2
    add hl,de          ; L*3
    add hl,hl
    add hl,hl
    add hl,hl          ; L*24
    ld (ul_i),hl
    ld hl,_u_typ
    ld b,0
    call ul_mv
    ld hl,_u_grp
    ld b,0
    call ul_mv
    ld hl,_u_len
    ld b,1
    call ul_mv
    ld hl,_u_pos
    ld b,2
    call ul_mv
    ld hl,_u_off
    ld b,1
    call ul_mv
    ; subtract cut from the moved u_off entries
    ld hl,(ul_i)
    add hl,hl
    ld de,_u_off
    add hl,de
    ld a,(ul_cnt)
    ld b,a
    ld de,(ul_cut)
ul_sub:
    ld a,(hl)
    sub e
    ld (hl),a
    inc hl
    ld a,(hl)
    sbc a,d
    ld (hl),a
    inc hl
    djnz ul_sub
    ret

; hl = array base, b = log2(element size): move cnt elements from index i+k to index i
ul_mv:
    ld a,b
    ld (ul_sh),a
    ld (ul_base),hl
    ld hl,(ul_i)
    call ul_shl
    ld de,(ul_base)
    add hl,de
    push hl            ; dest
    ld a,(ul_k)
    ld l,a
    ld h,0
    call ul_shl
    pop de
    add hl,de          ; hl = src
    push hl
    ld a,(ul_cnt)
    ld l,a
    ld h,0
    call ul_shl
    ld b,h
    ld c,l
    pop hl
    ldir
    ret

ul_shl:                ; hl <<= ul_sh
    ld a,(ul_sh)
    or a
    ret z
    ld b,a
ul_sl:
    add hl,hl
    djnz ul_sl
    ret

    SECTION bss_user
ul_cut: defw 0
ul_i:   defw 0
ul_base: defw 0
ul_cnt: defb 0
ul_k:   defb 0
ul_sh:  defb 0

; void ulog_put(u8 L, u8 typ, pos_t pos, u16 len, u8 grp)
;   store entry n=u_n[L] : typ, pos, len, off=u_dn[L], grp   (u_n/u_dn are advanced by the caller)
    SECTION code_user
    PUBLIC _ulog_put
    EXTERN _u_dn
_ulog_put:
    push ix
    ld ix,0
    add ix,sp          ; +4 grp, +6 len, +8 pos lo, +10 pos hi, +12 typ, +14 L
    ld a,(ix+14)
    ld c,a
    add a,a
    add a,c
    add a,a
    add a,a
    add a,a            ; L*24
    ld e,c
    ld d,0
    ld hl,_u_n
    add hl,de
    add a,(hl)
    ld e,a             ; de = idx = L*24 + n
    ld hl,_u_typ
    add hl,de
    ld a,(ix+12)
    ld (hl),a
    ld hl,_u_grp
    add hl,de
    ld a,(ix+4)
    ld (hl),a
    ex de,hl
    add hl,hl          ; hl = idx*2
    ex de,hl           ; de = idx*2
    ld hl,_u_len
    add hl,de
    ld a,(ix+6)
    ld (hl),a
    inc hl
    ld a,(ix+7)
    ld (hl),a
    push de
    ld a,(ix+14)
    add a,a
    ld e,a
    ld d,0
    ld hl,_u_dn
    add hl,de
    ld c,(hl)
    inc hl
    ld b,(hl)          ; bc = u_dn[L]
    pop de
    ld hl,_u_off
    add hl,de
    ld (hl),c
    inc hl
    ld (hl),b
    ex de,hl           ; hl = idx*2 -> idx*4
    add hl,hl
    ex de,hl
    ld hl,_u_pos
    add hl,de
    ld a,(ix+8)
    ld (hl),a
    inc hl
    ld a,(ix+9)
    ld (hl),a
    inc hl
    ld a,(ix+10)
    ld (hl),a
    inc hl
    ld a,(ix+11)
    ld (hl),a
    pop ix
    ret

; u16 ulog_merge(pos_t p)   -- coalesce a typed character into the previous INS of log 0.
;   returns the old u_dn[0] (>=1) after growing that entry by one byte, or 0 if it cannot be merged.
    SECTION code_user
    PUBLIC _ulog_merge
    EXTERN _ugrp
_ulog_merge:
    ld a,(_u_n)
    or a
    jr z,um_no
    dec a
    ld e,a
    ld d,0             ; de = idx = n-1
    ld hl,_u_typ
    add hl,de
    ld a,(hl)
    or a               ; T_INS == 0
    jr nz,um_no
    ld hl,_u_grp
    add hl,de
    ld a,(_ugrp)
    cp (hl)
    jr nz,um_no
    ld h,d
    ld l,e
    add hl,hl
    ld b,h
    ld c,l             ; bc = idx*2
    ld hl,_u_len
    add hl,bc
    ld e,(hl)
    inc hl
    ld d,(hl)          ; de = len
    push hl            ; &len (high byte)
    push de            ; len
    ld hl,_u_off
    add hl,bc
    ld a,(hl)
    inc hl
    ld h,(hl)
    ld l,a             ; hl = off
    add hl,de          ; off + len
    ld de,(_u_dn)
    or a
    sbc hl,de
    jr nz,um_no3
    ld a,d
    cp 2               ; u_dn >= UD (512)?
    jr nc,um_no3
    ld h,b
    ld l,c
    add hl,hl          ; idx*4
    ld de,_u_pos
    add hl,de
    ld e,(hl)
    inc hl
    ld d,(hl)
    inc hl
    ld c,(hl)
    inc hl
    ld b,(hl)          ; bc:de = pos
    pop hl             ; len
    add hl,de
    jr nc,um_c
    inc bc
um_c:
    ex de,hl           ; bc:de = pos + len
    ld hl,4
    add hl,sp          ; -> p (low word first)
    ld a,(hl)
    cp e
    jr nz,um_no1
    inc hl
    ld a,(hl)
    cp d
    jr nz,um_no1
    inc hl
    ld a,(hl)
    cp c
    jr nz,um_no1
    inc hl
    ld a,(hl)
    cp b
    jr nz,um_no1
    pop hl             ; &len high
    dec hl
    inc (hl)
    jr nz,um_k
    inc hl
    inc (hl)
um_k:
    ld hl,(_u_dn)
    push hl
    inc hl
    ld (_u_dn),hl
    pop hl             ; old u_dn
    ret
um_no3:
    pop hl
um_no1:
    pop hl
um_no:
    ld hl,0
    ret
