; visual_z80.asm - visual mode keys (the asm twin of vis_range / vis_motion / visual_key in core/ed_visual.c; -DM_ASM)
    SECTION code_user
    PUBLIC _visual_key, _vis_range
    EXTERN ldcur, stP, ldP, stQ, ldQ, stL, inc32, cmpm, mv_P, mv_Q, mv_L, pusha, pop2, instr, opa
    EXTERN _lstart, _lend, _setwant, _normal_key, _textobj, _blkop, _tx_len
    EXTERN _cur, _vstart, _vline, _vblk, _vp, _mode, _count, _pend, _gs, _ge, _glin

; mv_P .. mv_Q = the selected range [start, end)
vrng:
    ld hl,_vstart
    ld de,_cur
    call cmpm
    jr c,vr1
    call ldcur
    call stP
    ld hl,(_vstart)
    ld de,(_vstart+2)
    jr vr2
vr1:
    ld hl,(_vstart)
    ld de,(_vstart+2)
    call stP
    call ldcur
vr2:
    call stQ
    ld a,(_vline)
    ld hl,_vblk
    or (hl)
    jr z,vr3
    call ldP                    ; whole lines
    call _lstart
    call stP
    call ldQ
    call _lend
    jr vr4
vr3:
    call ldQ
vr4:
    call inc32
    call stQ
    call _tx_len
    call stL
    ld hl,mv_L
    ld de,mv_Q
    call cmpm
    ret nc
    ld hl,(mv_L)
    ld de,(mv_L+2)
    jp stQ

; void vis_range(pos_t *ps, pos_t *pe)
_vis_range:
    call vrng
    ld hl,2
    add hl,sp
    ld e,(hl)
    inc hl
    ld d,(hl)
    inc hl
    push hl
    ld hl,mv_Q
    ld bc,4
    ldir
    pop hl
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld hl,mv_P
    ld bc,4
    ldir
    ret

; void visual_key(u8 k) fastcall
_visual_key:
    ld a,l
    ld (vk_k),a
    ld a,(_vp)                  ; i / a was typed: this key names the text object to select
    or a
    jr z,v1
    ld (vk_o),a
    xor a
    ld (_vp),a
    ld a,(vk_k)
    cp 1Bh
    jr z,v1
    ld a,'v'
    call pusha
    ld a,(vk_o)
    call pusha
    ld a,(vk_k)
    call pusha
    call _textobj
    pop bc
    jp pop2
v1:
    ld hl,(_count)
    ld a,h
    or l
    ld hl,_pend
    or (hl)
    jr z,v2
vnk:
    ld a,(vk_k)
    ld l,a
    jp _normal_key
v2:
    ld a,(vk_k)
    cp 1Bh
    jr nz,v3
vnorm:
    xor a
    ld (_mode),a
    ret
v3:
    cp 'i'
    jr z,v3a
    cp 'a'
    jr nz,v4
v3a:
    ld (_vp),a
    ret
v4:
    cp 'v'
    jr nz,v5
    ld a,(_vline)
    ld hl,_vblk
    or (hl)
    jr z,vnorm
    xor a
    ld (_vline),a
    ld (_vblk),a
    ret
v5:
    cp 'V'
    jr nz,v6
    ld a,(_vblk)
    or a
    jr nz,v5a
    ld a,(_vline)
    or a
    jr nz,vnorm
v5a:
    ld a,1
    ld (_vline),a
    xor a
    ld (_vblk),a
    ret
v6:
    cp 16h
    jr nz,v7
    ld a,(_vblk)
    or a
    jr nz,vnorm
    inc a
    ld (_vblk),a
    xor a
    ld (_vline),a
    ret
v7:
    ld c,a
    ld a,(_vblk)
    or a
    jr z,v8
    ld a,c
    ld hl,s_blk
    call instr
    jr nz,v8
    ld l,a
    ld h,0
    jp _blkop
v8:
    ld a,c
    cp 'o'
    jr nz,v9
    ld hl,(_cur)                ; o: go to the other end
    ld de,(_vstart)
    ld (_vstart),hl
    ld (_cur),de
    ld hl,(_cur+2)
    ld de,(_vstart+2)
    ld (_vstart+2),hl
    ld (_cur+2),de
    jp _setwant
v9:
    ld hl,vk_ops                ; an operator on the selection?
v9a:
    ld a,(hl)
    or a
    jr z,v10
    cp c
    jr z,v9b
    inc hl
    inc hl
    jr v9a
v9b:
    inc hl
    ld a,(hl)
    ld b,a
    and 7Fh
    ld (vk_o),a
    ld a,(_vline)
    ld (vk_sv),a
    bit 7,b
    jr z,v9c
    ld a,1
v9c:
    ld (vk_lin),a
    ld (_vline),a
    call vrng
    ld a,(vk_sv)
    ld (_vline),a
    xor a
    ld (_mode),a
    call ldP
    ld (_gs),hl
    ld (_gs+2),de
    call ldQ
    ld (_ge),hl
    ld (_ge+2),de
    ld a,(vk_lin)
    ld (_glin),a
    ld a,(vk_o)
    jp opa
v10:
    ld a,c                      ; a motion: normal mode moves the cursor
    ld hl,s_vmot
    call instr
    jp z,vnk
    cp '1'
    ret c
    cp '9'+1
    ret nc
    jp vnk

s_blk:  defm "dxcsIA"
    defb 0
s_vmot: defm "hjkl0^$wbeWBEGgnN*#%HML{}"
    defb 1Ch, 1Dh, 1Eh, 1Fh, 04h, 15h, 06h, 02h, 05h, 19h, 0
; key, operator (+80h = on whole lines)
vk_ops:
    defb 'd', 'd', 'x', 'd', 'X', 'd'+80h, 'D', 'd'+80h
    defb 'y', 'y', 'Y', 'y'+80h
    defb '>', '>'+80h, '<', '<'+80h
    defb 'c', 'c', 's', 'c', 'C', 'c'+80h, 'S', 'c'+80h, 'R', 'c'+80h
    defb 'u', 'u', 'U', 'U', '~', '~'
    defb 0

    SECTION bss_user
vk_k:   defb 0
vk_o:   defb 0
vk_sv:  defb 0
vk_lin: defb 0
