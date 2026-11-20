; insert_z80.asm - insert mode (the asm twin of core/ed_insert.c and begin_ins; -DM_ASM)
    SECTION code_user
    PUBLIC _insert_key, _begin_ins, _pind, gind_r, tgetat, tdel1
    EXTERN ldcur, stcur, stP, ldP, inc32, dec32, cmpm, subm, addm, pusha, tabjp, mv_P, mv_n, mv_dn, vmove_r
    EXTERN _lstartc, _lendc, _tgetc, _setwant, _clampcur, _setmsg, _blkrep
    EXTERN _tx_get, _tx_read, _tins, _tdel, _tinsn
    EXTERN _cur, _want, _mode, _rmode, _ikind, _icnt, _istart, _ibuf, _bkn, _ai, _ind, _ilen
    defc ISZ = 64               ; (core/editor.c)

; A = the character at DEHL
tgetat:
    push de
    push hl
    call _tx_get
    pop bc
    pop bc
    ld a,l
    ret
; tins(cur, A): Z if there is no room
tinsc:
    ld c,a
    call ldcur
    push de
    push hl
    ld a,c
    call pusha
    call _tins
    pop bc
    pop bc
    pop bc
    ld a,l
    or a
    ret
; tdel(DEHL, 1)
tdel1:
    push de
    push hl
    ld hl,0
    push hl
    inc hl
    push hl
    call _tdel
    pop bc
    pop bc
    pop bc
    pop bc
    ret
curinc:
    call ldcur
    call inc32
    jp stcur
curdec:
    call ldcur
    call dec32
    jp stcur
; Z if cur == 0, else DEHL = cur - 1
curm1:
    call ldcur
    ld a,h
    or l
    or d
    or e
    ret z
    call dec32
    or 1
    ret

; void begin_ins(u8 k, u16 n) : enter insert mode for the command k with the count n
_begin_ins:
    ld hl,2
    add hl,sp
    ld e,(hl)
    inc hl
    ld d,(hl)
    inc hl
    ld a,(hl)
    ld (_ikind),a
    ld (_icnt),de
    call ldcur
    ld (_istart),hl
    ld (_istart+2),de
    ld a,1
    ld (_mode),a
    ret

; gind_r: DEHL = start of a line, A = limit: remember its leading blanks (:set ai) in ind[] / ilen
gind_r:
    ld (gi_lim),a
    ld (gi_src),hl
    ld (gi_src+2),de
    xor a
    ld (_ilen),a
    ld a,(_ai)
    or a
    ret z
gi1:
    ld a,(_ilen)
    ld hl,gi_lim
    cp (hl)
    ret nc
    cp 32
    ret nc
    ld l,a
    ld h,0
    ld de,gi_src
    call addm
    call tgetat
    cp ' '
    jr z,gi2
    cp 9
    ret nz
gi2:
    ld c,a
    ld a,(_ilen)
    ld e,a
    ld d,0
    ld hl,_ind
    add hl,de
    ld (hl),c
    inc a
    ld (_ilen),a
    jr gi1

; void pind(void) : type the remembered indent at the cursor
_pind:
    xor a
    ld (pi_i),a
pi1:
    ld a,(pi_i)
    ld hl,_ilen
    cp (hl)
    jp nc,_setwant
    ld e,a
    ld d,0
    ld hl,_ind
    add hl,de
    ld a,(hl)
    call tinsc
    jp z,_setwant
    call curinc
    ld hl,pi_i
    inc (hl)
    jr pi1

; void insert_key(u8 k) fastcall
_insert_key:
    ld a,l
    ld (ik_k),a
    ld hl,ik_tab
    jp tabjp
ik_tab:
    defb 1Bh
    defw leave_insert
    defb 0Dh
    defw ik_cr
    defb 08h
    defw ik_bs
    defb 12h
    defw ik_del
    defb 7Fh
    defw ik_del
    defb 1Ch
    defw ik_right
    defb 1Dh
    defw ik_left
    defb 1Eh
    defw ik_up
    defb 1Fh
    defw ik_down
    defb 0
    defw ik_def

ik_def:                         ; a printable character or a tab
    cp 20h
    jr nc,ikd1
    cp 9
    ret nz
ikd1:
    ld a,(_rmode)               ; R: type over
    or a
    jr z,ikd2
    call _tgetc
    ld a,l
    cp 10
    jr z,ikd2
    call ldcur
    call tdel1
ikd2:
    ld a,(ik_k)
    call tinsc
    ret z
ik_adv:
    call curinc
    jp _setwant
ik_cr:                          ; Enter: a new line, with the indent of this one if :set ai
    call _lstartc
    call stP
    ld hl,_cur
    ld de,mv_P
    call subm
    ld a,d
    or e
    or h
    jr nz,ic1
    ld a,l
    cp 33
    jr c,ic2
ic1:
    ld a,32
ic2:
    ld c,a
    call ldP
    ld a,c
    call gind_r
    ld a,10
    call tinsc
    ret z
    call curinc
    ld hl,0
    ld (_want),hl
    jp _pind
ik_bs:                          ; BS
    call curm1
    ret z
    call tdel1
    call curdec
    jp _setwant
ik_del:                         ; DEL
    call _tgetc
    ld a,l
    cp 10
    ret z
    call ldcur
    jp tdel1
ik_right:
    call _tgetc
    ld a,l
    cp 10
    ret z
    jr ik_adv
ik_left:
    call curm1
    ret z
    call tgetat
    cp 10
    ret z
    call curdec
    jp _setwant
ik_up:
    xor a
    jr ikv
ik_down:
    ld a,1
ikv:
    ld (mv_dn),a
    ld hl,1
    ld (mv_n),hl
    jp vmove_r

; Esc: back to normal mode (after repeating the text for a count, and filling the other rows of a block I / A)
leave_insert:
    xor a
    ld (_rmode),a
    ld hl,(_icnt)
    ld de,2
    or a
    sbc hl,de
    call nc,repins
    ld hl,(_bkn)
    ld a,h
    or l
    call nz,_blkrep
    ld hl,0
    ld (_icnt),hl
    xor a
    ld (_mode),a
    call curm1
    jr z,li1
    call tgetat
    cp 10
    call nz,curdec
li1:
    call _clampcur
    jp _setwant

; 3ihi<Esc>: insert the typed text count - 1 more times
repins:
    ld hl,_istart
    ld de,_cur
    call cmpm
    ret nc                      ; nothing was typed
    ld hl,_cur
    ld de,_istart
    call subm
    ld a,d
    or e
    jp nz,ri_long
    push hl
    ld de,ISZ+1
    or a
    sbc hl,de
    pop hl
    jp nc,ri_long
    ld (ri_len),hl
    ld hl,_ibuf
    push hl
    ld hl,(_istart+2)
    push hl
    ld hl,(_istart)
    push hl
    ld hl,0
    push hl
    ld hl,(ri_len)
    push hl
    call _tx_read
    pop bc
    pop bc
    pop bc
    pop bc
    pop bc
    ld hl,(_icnt)
    dec hl
    ld (ri_r),hl
    ld a,(_ikind)
    or 20h
    cp 'o'
    jr nz,ri_in
    ld hl,(ri_len)              ; o O: whole lines after this one
    ld de,_ibuf
    add hl,de
    ld (hl),10
    ld hl,(ri_len)
    inc hl
    ld (ri_len),hl
    call _lendc
    call inc32
    call stP
ri_o1:
    call ldP
    call tinsn_r
    ret z
    call ri_dec
    jr nz,ri_o1
    ret
ri_in:
    call ldcur
    call tinsn_r
    ret z
    ld hl,(ri_len)
    ld de,_cur
    call addm
    call stcur
    call ri_dec
    jr nz,ri_in
    ret
ri_dec:
    ld hl,(ri_r)
    dec hl
    ld (ri_r),hl
    ld a,h
    or l
    ret
; tinsn(DEHL, ibuf, ri_len): Z if there is no room
tinsn_r:
    push de
    push hl
    ld hl,_ibuf
    push hl
    ld hl,0
    push hl
    ld hl,(ri_len)
    push hl
    call _tinsn
    pop bc
    pop bc
    pop bc
    pop bc
    pop bc
    ld a,l
    or a
    ret
ri_long:
    ld hl,s_long
    push hl
    call _setmsg
    pop bc
    ret
s_long: defm "too long to repeat"
    defb 0

    SECTION bss_user
ik_k:   defb 0
pi_i:   defb 0
gi_lim: defb 0
gi_src: defs 4
ri_len: defs 2
ri_r:   defs 2
