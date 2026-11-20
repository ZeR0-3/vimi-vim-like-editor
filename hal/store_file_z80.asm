; store_file_z80.asm - swap-file text store, Z80 version of the data path of store_file.c
;   block = 1KB (8 CP/M records), 4 slots at A000h.., write-back cache, BDOS random access.
;   C side (store_file.c) keeps stf_init / stf_exit / stf_cap and shares the state below.
;   sccz80 conventions: args pushed left to right (a long is lo word then hi word, ascending), caller pops,
;   u8 result in L, long result in DE:HL.
    SECTION code_user
    PUBLIC _stf_get, _stf_read, _stf_write, _stf_findb, _stf_rfindb, _stf_countb
    PUBLIC _sblk, _sdirty, _sfcb, _rr, _lasti

BDOS    equ 5
SLOT0   equ 0A0h            ; high byte of slot 0 (A000h); slot i = A000h + i*400h

; ---------------------------------------------------------------- block cache
; sblp: A = slot -> HL = &sblk[A]   (keeps A)
sblp:
    ld l,a
    ld h,0
    add hl,hl
    ld bc,_sblk
    add hl,bc
    ret

; bp_cmp: A = slot, DE = block -> Z if sblk[A] == DE (keeps A)
bp_cmp:
    call sblp
    ld c,(hl)
    inc hl
    ld b,(hl)
    ld h,b
    ld l,c
    or a
    sbc hl,de
    ret

; bp: HL = block -> HL = address of the slot holding it (loading it if needed)
bp:
    ex de,hl
    ld a,(_lasti)
    call bp_cmp
    jr z,bp_hit
    xor a
bp_s:
    call bp_cmp
    jr z,bp_hit
    inc a
    cp 4
    jr c,bp_s
    ld a,(_rr)             ; miss: take the next slot round-robin
    ld c,a
    inc a
    and 3
    ld (_rr),a
    ld a,c
    push de
    push af
    ld l,a
    ld h,0
    ld de,_sdirty
    add hl,de
    ld a,(hl)
    or a
    jr z,bp_cl
    ld (hl),0              ; write the old block back
    pop af
    push af
    call sblp
    ld e,(hl)
    inc hl
    ld d,(hl)
    pop af
    push af
    ld b,1
    call xfer
bp_cl:
    pop af
    pop de
    push de
    push af
    ld b,0                 ; read the wanted block
    call xfer
    pop af
    pop de
    call sblp
    ld (hl),e
    inc hl
    ld (hl),d
bp_hit:
    ld (_lasti),a
    ld (curslot),a
    add a,a
    add a,a
    add a,SLOT0
    ld h,a
    ld l,0
    ret

; xfer: A = slot, DE = block, B = 1 write / 0 read.  8 records through BDOS random access (errors are ignored,
;       as before)
xfer:
    ld c,a
    ld a,33                ; BDOS read random
    inc b
    dec b
    jr z,xf_r
    ld a,34                ; write random
xf_r:
    ld (xf_fn),a
    ld a,c
    add a,a
    add a,a
    add a,SLOT0
    ld h,a
    ld l,0
    ld (xf_dma),hl
    ex de,hl
    add hl,hl
    add hl,hl
    add hl,hl
    ld (xf_rec),hl
    ld a,8
    ld (xf_cnt),a
xf_l:
    ld hl,(xf_rec)
    ld (_sfcb+33),hl
    xor a
    ld (_sfcb+35),a
    ld de,(xf_dma)
    ld c,26
    call BDOS
    ld de,_sfcb
    ld a,(xf_fn)
    ld c,a
    call BDOS
    or a
    ret nz
    ld hl,(xf_rec)
    inc hl
    ld (xf_rec),hl
    ld hl,(xf_dma)
    ld de,128
    add hl,de
    ld (xf_dma),hl
    ld hl,xf_cnt
    dec (hl)
    jr nz,xf_l
    ret

; ---------------------------------------------------------------- spans
; loc: s_off -> HL = address of that byte in its slot, DE = k (offset inside the block)
loc:
    ld hl,(s_off+2)
    ld a,(s_off+1)
    rrca
    rrca
    and 3Fh
    ld c,a
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    ld a,l
    or c
    ld l,a                 ; block = off >> 10
    call bp
    ld a,(s_off+1)
    and 3
    ld d,a
    ld a,(s_off)
    ld e,a
    add hl,de
    ret

; clamp: HL = wanted span -> BC = min(HL, s_n), and s_n -= BC
clamp:
    ld bc,(s_n+2)
    ld a,b
    or c
    jr nz,cl_ok
    ld de,(s_n)
    or a
    sbc hl,de
    add hl,de
    jr c,cl_ok             ; span < remaining
    ex de,hl
cl_ok:
    ld b,h
    ld c,l
    ld hl,(s_n)
    or a
    sbc hl,bc
    ld (s_n),hl
    ret nc
    ld hl,(s_n+2)
    dec hl
    ld (s_n+2),hl
    ret

; nxt: forward span of the pending range -> HL = pointer, BC = length; s_off += BC, s_n -= BC
nxt:
    call loc
    push hl
    ld hl,1024
    or a
    sbc hl,de
    call clamp
    ld hl,(s_off)
    add hl,bc
    ld (s_off),hl
    jr nc,nx_x
    ld hl,(s_off+2)
    inc hl
    ld (s_off+2),hl
nx_x:
    pop hl
    ret

; nxtb: backward span ending at s_off -> HL = pointer (at s_off), BC = length; s_n -= BC (s_off is not moved)
nxtb:
    call loc
    push hl
    ex de,hl
    inc hl
    call clamp
    pop hl
    ret

; nz: Z if s_n == 0
nz:
    ld hl,(s_n)
    ld a,h
    or l
    ld hl,(s_n+2)
    or h
    or l
    ret

; ---------------------------------------------------------------- entry points
_stf_get:                  ; u8 stf_get(pos_t i)
    ld hl,2
    add hl,sp
    ld de,s_off
    ld bc,4
    ldir
    ld hl,1
    ld (s_n),hl
    ld hl,0
    ld (s_n+2),hl
    call nxt
    ld l,(hl)
    ld h,0
    ret

; copy 4 bytes from (sp+n) to s_n: helper macros are avoided to keep it small
cpn:                       ; HL = source -> s_n
    ld de,s_n
    jr cp4
cpo:                       ; HL = source -> s_off
    ld de,s_off
cp4:
    ld bc,4
    ldir
    ret

_stf_read:                 ; void stf_read(u8 *d, pos_t off, pos_t n)
    ld hl,2
    add hl,sp
    call cpn               ; n   (sp+2)
    ld hl,6
    add hl,sp
    call cpo               ; off (sp+6)
    ld hl,10
    add hl,sp
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld (s_d),de
sr_l:
    call nz
    ret z
    call nxt
    ld de,(s_d)
    ldir
    ld (s_d),de
    jr sr_l

_stf_write:                ; void stf_write(pos_t off, const u8 *s, pos_t n)
    ld hl,2
    add hl,sp
    call cpn               ; n   (sp+2)
    ld hl,8
    add hl,sp
    call cpo               ; off (sp+8)
    ld hl,6
    add hl,sp
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld (s_d),de
sw_l:
    call nz
    ret z
    call nxt
    push hl
    push bc
    ld a,(curslot)
    ld e,a
    ld d,0
    ld hl,_sdirty
    add hl,de
    ld (hl),1
    pop bc
    pop de
    ld hl,(s_d)
    ldir
    ld (s_d),hl
    jr sw_l

; n = hi:lo word at (ix+a..) minus ... shared setup for findb / countb:  s_off = off, s_n = end - off
; returns carry if end < off (caller handles), Z/NZ not defined
rng:
    ld l,(ix+6)
    ld h,(ix+7)
    ld e,(ix+10)
    ld d,(ix+11)
    ld (s_off),de
    or a
    sbc hl,de
    ld (s_n),hl
    ld l,(ix+8)
    ld h,(ix+9)
    ld e,(ix+12)
    ld d,(ix+13)
    ld (s_off+2),de
    sbc hl,de
    ld (s_n+2),hl
    ret

_stf_findb:                ; pos_t stf_findb(pos_t off, pos_t end, u8 c)
    push ix
    ld ix,0
    add ix,sp
    call rng
    jr c,fb_end
fb_l:
    call nz
    jr z,fb_end
    call nxt
    ld a,(ix+4)
    cpir
    jr nz,fb_l
    inc bc                 ; found: index = s_off - (BC + 1)
    ld hl,(s_off)
    or a
    sbc hl,bc
    ex de,hl
    ld hl,(s_off+2)
    ld bc,0
    sbc hl,bc
    ex de,hl
    pop ix
    ret
fb_end:
    ld l,(ix+6)
    ld h,(ix+7)
    ld e,(ix+8)
    ld d,(ix+9)
    pop ix
    ret

_stf_countb:               ; pos_t stf_countb(pos_t off, pos_t end, u8 c)
    push ix
    ld ix,0
    add ix,sp
    ld hl,0
    ld (s_cnt),hl
    ld (s_cnt+2),hl
    call rng
    jr c,cb_x
cb_l:
    call nz
    jr z,cb_x
    call nxt
cb_s:
    ld a,(ix+4)
    cpir
    jr nz,cb_l
    push hl                ; (the scan pointer: counting must not lose it - it used to, so every count after the first hit was garbage)
    ld hl,(s_cnt)
    inc hl
    ld (s_cnt),hl
    ld a,h
    or l
    jr nz,cb_n
    ld hl,(s_cnt+2)
    inc hl
    ld (s_cnt+2),hl
cb_n:
    pop hl
    ld a,b
    or c
    jr nz,cb_s
    jr cb_l
cb_x:
    ld hl,(s_cnt)
    ld de,(s_cnt+2)
    pop ix
    ret

_stf_rfindb:               ; pos_t stf_rfindb(pos_t off, pos_t floor, u8 c)  -- last index in [floor,off) holding c
    push ix
    ld ix,0
    add ix,sp
    ld l,(ix+10)           ; n = off - floor
    ld h,(ix+11)
    ld e,(ix+6)
    ld d,(ix+7)
    or a
    sbc hl,de
    ld (s_n),hl
    ld l,(ix+12)
    ld h,(ix+13)
    ld e,(ix+8)
    ld d,(ix+9)
    sbc hl,de
    ld (s_n+2),hl
    jr c,rf_none
    ld l,(ix+10)           ; s_off = off - 1
    ld h,(ix+11)
    ld e,(ix+12)
    ld d,(ix+13)
    ld a,h
    or l
    dec hl
    jr nz,rf_s
    dec de
rf_s:
    ld (s_off),hl
    ld (s_off+2),de
rf_l:
    call nz
    jr z,rf_none
    call nxtb
    push bc
    ld a,(ix+4)
    cpdr
    jr z,rf_f
    pop bc
    ld hl,(s_off)
    or a
    sbc hl,bc
    ld (s_off),hl
    jr nc,rf_l
    ld hl,(s_off+2)
    dec hl
    ld (s_off+2),hl
    jr rf_l
rf_f:                      ; BC = bytes left after the hit: j = m - 1 - BC, index = s_off - j
    pop hl
    or a
    sbc hl,bc
    dec hl
    ld b,h
    ld c,l
    ld hl,(s_off)
    or a
    sbc hl,bc
    ex de,hl
    ld hl,(s_off+2)
    ld bc,0
    sbc hl,bc
    ex de,hl
    pop ix
    ret
rf_none:
    ld hl,0FFFFh
    ld d,h
    ld e,l
    pop ix
    ret

    SECTION bss_user
_sblk:   defs 8
_sdirty: defs 4
_sfcb:   defs 36
_rr:     defb 0
_lasti:  defb 0
curslot: defb 0
xf_fn:   defb 0
xf_cnt:  defb 0
xf_dma:  defw 0
xf_rec:  defw 0
s_off:   defs 4
s_n:     defs 4
s_cnt:   defs 4
s_d:     defw 0
