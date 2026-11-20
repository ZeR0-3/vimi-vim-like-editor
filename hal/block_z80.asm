; block_z80.asm - Ctrl-V block mode and the named registers (asm twins of the block code in core/ed_visual.c and of
; regcompact / regstore in core/ed_reg.c; -DM_ASM)
    SECTION code_user
    PUBLIC _blkgeom, _blkop, _blkrep, _regstore
    EXTERN ldcur, stcur, stP, ldP, stQ, ldQ, inc32, cmpm, subm, addm, pusha, tinsat
    EXTERN _lstart, _lstartc, _lend, _lendc, _sethcur, _lineno, _begin_ins, _setmsg
    EXTERN _tx_len, _tx_read, _tdel, _tinsn, _tx_aux_move, _tx_aux_put, _tx_aux_get
    EXTERN _cur, _vstart, _mode, _istart, _ibuf, _bkn, _bkc, _bka, _bc1, _bc2, _bnr, _btop
    EXTERN _reg, _rlen, _roff, _rflg, _rtop, _m_full
    defc ISZ = 64
    defc RSZ = 1024
    defc RBASE = 2048

; void blkgeom(void) : the block between vstart and the cursor: columns bc1..bc2, bnr rows, btop = start of the top row
_blkgeom:
    ld hl,_vstart
    ld de,_cur
    call cmpm
    jr c,bg1
    call ldcur
    call stP
    ld hl,(_vstart)
    ld de,(_vstart+2)
    jr bg2
bg1:
    ld hl,(_vstart)
    ld de,(_vstart+2)
    call stP
    call ldcur
bg2:
    call stQ
    call ldP
    call _lstart
    ld (_btop),hl
    ld (_btop+2),de
    ld hl,(_vstart)
    ld de,(_vstart+2)
    call _lstart
    ex de,hl
    ld hl,(_vstart)
    or a
    sbc hl,de
    ld (bs_t),hl
    call _lstartc
    ex de,hl
    ld hl,(_cur)
    or a
    sbc hl,de
    ld de,(bs_t)
    or a
    sbc hl,de
    add hl,de
    jr nc,bg3
    ex de,hl
bg3:
    ld (_bc1),de
    ld (_bc2),hl
    call ldQ
    call _lstart
    push de
    push hl
    call _lineno
    pop bc
    pop bc
    push hl
    ld hl,(_btop+2)
    push hl
    ld hl,(_btop)
    push hl
    call _lineno
    pop bc
    pop bc
    ex de,hl
    pop hl
    or a
    sbc hl,de
    inc hl
    ld (_bnr),hl
    ret

; bs_a .. bs_b = the block's part of the line at bs_ls
blkseg:
    ld hl,(bs_ls)
    ld de,(bs_ls+2)
    call _lend
    ld (bs_le),hl
    ld (bs_le+2),de
    ld hl,(_bc1)
    call bs_clip
    ld (bs_a),hl
    ld (bs_a+2),de
    ld hl,(_bc2)
    inc hl
    call bs_clip
    ld (bs_b),hl
    ld (bs_b+2),de
    ret
bs_clip:                        ; DEHL = min(bs_ls + HL, end of the line)
    ld de,bs_ls
    call addm
    ld (bs_t),hl
    ld (bs_t+2),de
    ld hl,bs_le
    ld de,bs_t
    call cmpm
    jr c,bc1
    ld hl,(bs_t)
    ld de,(bs_t+2)
    ret
bc1:
    ld hl,(bs_le)
    ld de,(bs_le+2)
    ret
; make the line at bs_ls at least HL characters long
blkpad:
    ld (bp_col),hl
bp1:
    ld hl,(bs_ls)
    ld de,(bs_ls+2)
    call _lend
    push de
    push hl
    ld bc,(bs_ls)
    or a
    sbc hl,bc
    ld bc,(bp_col)
    or a
    sbc hl,bc
    pop hl
    pop de
    ret nc
    ld a,' '
    call tinsat
    ld a,l
    or a
    ret z
    jr bp1
; C if bs_ls is inside the text
bo_inside:
    call _tx_len
    ld (bs_t),hl
    ld (bs_t+2),de
    ld hl,bs_ls
    ld de,bs_t
    jp cmpm
bo_next:                        ; bs_ls = the next line
    ld hl,(bs_ls)
    ld de,(bs_ls+2)
    call _lend
    call inc32
bo_setls:
    ld (bs_ls),hl
    ld (bs_ls+2),de
    ret

; void blkop(u8 k) fastcall : d x c s I A on the block
_blkop:
    ld a,l
    ld (bo_k),a
    call _blkgeom
    xor a
    ld (_mode),a
    ld a,(bo_k)
    cp 'I'
    jp z,bo_ins
    cp 'A'
    jp z,bo_ins
    ld hl,(_bnr)                ; delete, from the bottom row up
    ld (bo_i),hl
bo1:
    ld hl,(bo_i)
    ld a,h
    or l
    jr z,bo5
    ld hl,(_btop)
    ld de,(_btop+2)
    call bo_setls
    ld hl,1
    ld (bo_m),hl
bo2:
    ld hl,(bo_m)
    ld de,(bo_i)
    or a
    sbc hl,de
    jr nc,bo3
    call bo_inside
    jr nc,bo3
    call bo_next
    ld hl,(bo_m)
    inc hl
    ld (bo_m),hl
    jr bo2
bo3:
    call bo_inside
    jr nc,bo4
    call blkseg
    ld hl,bs_b
    ld de,bs_a
    call subm
    jr c,bo4
    ld a,h
    or l
    or d
    or e
    jr z,bo4
    ld bc,(bs_a+2)
    push bc
    ld bc,(bs_a)
    push bc
    push de
    push hl
    call _tdel
    pop bc
    pop bc
    pop bc
    pop bc
bo4:
    ld hl,(bo_i)
    dec hl
    ld (bo_i),hl
    jr bo1
bo5:
    ld a,(bo_k)
    cp 'd'
    jr z,bo6
    cp 'x'
    jr nz,bo7
bo6:
    ld hl,(_bc1)
    ld de,_btop
    call addm
    jp _sethcur
bo7:
    ld a,'I'                    ; c s: go on as I
    ld (bo_k),a
bo_ins:
    ld hl,(_bc1)
    ld a,(bo_k)
    cp 'A'
    jr nz,bo8
    ld hl,(_bc2)
    inc hl
bo8:
    ld (bo_m),hl
    ld hl,(_btop)
    ld de,(_btop+2)
    call bo_setls
    ld hl,(bo_m)
    call blkpad
    ld hl,(bo_m)
    ld (_bkc),hl
    ld de,_btop
    call addm
    call stcur
    ld hl,(_bnr)
    dec hl
    ld (_bkn),hl
    ld a,(bo_k)
    sub 'A'
    sub 1
    sbc a,a
    and 1
    ld (_bka),a
    ld a,'i'
    call pusha
    ld hl,1
    push hl
    call _begin_ins
    pop bc
    pop bc
    ret

; void blkrep(void) : leaving a block I / A - the typed text goes into the other rows too
_blkrep:
    ld hl,(_bkn)
    ld (bo_i),hl
    ld hl,0
    ld (_bkn),hl
    ld hl,_istart
    ld de,_cur
    call cmpm
    ret nc
    ld hl,_cur
    ld de,_istart
    call subm
    ld a,d
    or e
    or h
    ret nz
    ld a,l
    cp ISZ+1
    ret nc
    ld (bo_m),hl
    ld hl,_ibuf
    push hl
    ld hl,(_istart+2)
    push hl
    ld hl,(_istart)
    push hl
    ld hl,0
    push hl
    ld hl,(bo_m)
    push hl
    call _tx_read
    pop bc
    pop bc
    pop bc
    pop bc
    pop bc
    ld hl,_ibuf
    ld bc,(bo_m)
    ld a,10
    cpir
    ret z                       ; more than one line was typed: leave it
    call _lendc
    call inc32
    call bo_setls
br1:
    ld hl,(bo_i)
    ld a,h
    or l
    ret z
    dec hl
    ld (bo_i),hl
    call bo_inside
    ret nc
    ld a,(_bka)
    or a
    jr nz,br2
    ld hl,(bs_ls)               ; I: a row that ends before the column is left alone
    ld de,(bs_ls+2)
    call _lend
    ld bc,(bs_ls)
    or a
    sbc hl,bc
    ld bc,(_bkc)
    or a
    sbc hl,bc
    jr c,br3
br2:
    ld hl,(_bkc)
    call blkpad
    ld hl,(_bkc)
    ld de,bs_ls
    call addm
    push de
    push hl
    ld hl,_ibuf
    push hl
    ld hl,0
    push hl
    ld hl,(bo_m)
    push hl
    call _tinsn
    pop bc
    pop bc
    pop bc
    pop bc
    pop bc
    ld a,l
    or a
    ret z
br3:
    call bo_next
    jr br1

; ---- named registers: 26 slots in the aux area at RBASE (roff / rlen / rflg), packed towards rtop
; HL -> entry A of a table of words
wptr:
    add a,a
    ld e,a
    ld d,0
    add hl,de
    ret
; HL = word at entry A of the table HL
wget:
    call wptr
    ld a,(hl)
    inc hl
    ld h,(hl)
    ld l,a
    ret
; close the gaps left by registers that were overwritten
regc:
    ld hl,0
    ld (rc_nt),hl
rg1:
    xor a
    ld (rc_f),a
    ld (rc_j),a
rg2:
    ld a,(rc_j)
    cp 26
    jr nc,rg5
    ld hl,_rlen
    call wget
    ld a,h
    or l
    jr z,rg4
    ld a,(rc_j)
    ld hl,_roff
    call wget
    push hl
    ld de,(rc_nt)
    or a
    sbc hl,de
    pop hl
    jr c,rg4
    ld a,(rc_f)
    or a
    jr z,rg3
    push hl
    ld de,(rc_bo)
    or a
    sbc hl,de
    pop hl
    jr nc,rg4
rg3:
    ld (rc_bo),hl
    ld a,1
    ld (rc_f),a
    ld a,(rc_j)
    ld (rc_bj),a
rg4:
    ld hl,rc_j
    inc (hl)
    jr rg2
rg5:
    ld a,(rc_f)
    or a
    jr z,rg9
    ld a,(rc_bj)
    ld hl,_rlen
    call wget
    ld (rc_len),hl
    ld hl,(rc_bo)
    ld de,(rc_nt)
    or a
    sbc hl,de
    jr z,rg6
    ld hl,(rc_nt)
    ld de,RBASE
    add hl,de
    push hl
    ld hl,(rc_bo)
    add hl,de
    push hl
    ld hl,(rc_len)
    push hl
    call _tx_aux_move
    pop bc
    pop bc
    pop bc
rg6:
    ld a,(rc_bj)
    ld hl,_roff
    call wptr
    ld de,(rc_nt)
    ld (hl),e
    inc hl
    ld (hl),d
    ld hl,(rc_len)
    add hl,de
    ld (rc_nt),hl
    jp rg1
rg9:
    ld hl,(rc_nt)
    ld (_rtop),hl
    ret
; C if rtop + rs_tot <= RSZ
rs_fits:
    ld hl,(_rtop)
    ld de,(rs_tot)
    add hl,de
    ld de,RSZ+1
    or a
    sbc hl,de
    ret

; void regstore(const u8 *src, u16 n, u8 f) : n bytes at src (or the unnamed register if src = 0) -> register reg
; (an upper-case name appends); f = bit0 linewise, bit1 holds a line break
_regstore:
    ld hl,2
    add hl,sp
    ld a,(hl)
    ld (rs_f),a
    inc hl
    inc hl
    ld e,(hl)
    inc hl
    ld d,(hl)
    inc hl
    ld (rs_n),de
    ld a,(hl)
    inc hl
    ld h,(hl)
    ld l,a
    ld (rs_src),hl
    ld a,d
    or e
    ret z
    ld a,(_reg)
    cp 'a'
    ld a,0
    jr nc,rs1
    inc a
rs1:
    ld (rs_ap),a
    ld a,(_reg)
    or 20h
    sub 'a'
    ld (rs_r),a
    ld hl,0
    ld a,(rs_ap)
    or a
    jr z,rs2
    ld a,(rs_r)
    ld hl,_rlen
    call wget
rs2:
    ld (rs_old),hl
    ld de,(rs_n)
    add hl,de
    ld (rs_tot),hl
    ld de,RSZ+1
    or a
    sbc hl,de
    jr nc,rs_full
    call rs_fits
    jr c,rs3
    call regc
    call rs_fits
    jr c,rs3
rs_full:
    ld hl,_m_full
    push hl
    call _setmsg
    pop bc
    ret
rs3:
    ld hl,(rs_old)              ; appending: the old text moves to the new place first
    ld a,h
    or l
    jr z,rs4
    ld hl,(_rtop)
    ld de,RBASE
    add hl,de
    push hl
    ld a,(rs_r)
    ld hl,_roff
    call wget
    ld de,RBASE
    add hl,de
    push hl
    ld hl,(rs_old)
    push hl
    call _tx_aux_move
    pop bc
    pop bc
    pop bc
rs4:
    ld hl,0
    ld (rs_i),hl
rs5:
    ld hl,(rs_n)
    ld de,(rs_i)
    or a
    sbc hl,de
    jr z,rs8
    ld a,h
    or a
    jr nz,rs5a
    ld a,l
    cp ISZ+1
    jr c,rs5b
rs5a:
    ld hl,ISZ
rs5b:
    ld (rs_m),hl
    ld hl,(_rtop)
    ld de,RBASE
    add hl,de
    ld de,(rs_old)
    add hl,de
    ld de,(rs_i)
    add hl,de
    push hl                     ; where it goes
    ld hl,(rs_src)
    ld a,h
    or l
    jr z,rs6
    add hl,de
    jr rs7
rs6:
    ld hl,_ibuf                 ; from the unnamed register, through the scratch buffer
    push hl
    push de
    ld hl,(rs_m)
    push hl
    call _tx_aux_get
    pop bc
    pop bc
    pop bc
    ld hl,_ibuf
rs7:
    push hl
    ld hl,(rs_m)
    push hl
    call _tx_aux_put
    pop bc
    pop bc
    pop bc
    ld hl,(rs_i)
    ld de,(rs_m)
    add hl,de
    ld (rs_i),hl
    jr rs5
rs8:
    ld a,(rs_r)
    ld hl,_roff
    call wptr
    ld de,(_rtop)
    ld (hl),e
    inc hl
    ld (hl),d
    ld a,(rs_r)
    ld hl,_rlen
    call wptr
    ld de,(rs_tot)
    ld (hl),e
    inc hl
    ld (hl),d
    ld hl,(_rtop)
    add hl,de
    ld (_rtop),hl
    ld a,(rs_r)
    ld e,a
    ld d,0
    ld hl,_rflg
    add hl,de
    ld a,(rs_ap)
    or a
    jr z,rs9
    ld a,(hl)
rs9:
    ld b,a
    ld a,(rs_f)
    or b
    ld (hl),a
    ret

    SECTION bss_user
bs_ls:  defs 4
bs_le:  defs 4
bs_a:   defs 4
bs_b:   defs 4
bs_t:   defs 4
bp_col: defs 2
bo_i:   defs 2
bo_m:   defs 2
bo_k:   defb 0
rc_f:   defb 0
rc_j:   defb 0
rc_bj:  defb 0
rc_nt:  defs 2
rc_bo:  defs 2
rc_len: defs 2
rs_src: defs 2
rs_n:   defs 2
rs_old: defs 2
rs_tot: defs 2
rs_i:   defs 2
rs_m:   defs 2
rs_f:   defb 0
rs_ap:  defb 0
rs_r:   defb 0
