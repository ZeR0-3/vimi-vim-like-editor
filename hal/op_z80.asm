; op_z80.asm - operator + motion (the asm twin of get_range / op_motion in core/ed_op.c; -DM_ASM)
;   op_go: D = operator, E = motion key, HL = count, A = a count was typed.  Finds the range [gs, ge) (glin = linewise)
;   and, if the motion is possible, runs op_apply(operator).  Motion 80h = gg.
    SECTION code_user
    PUBLIC op_go, _op_apply, opa
    EXTERN stcur, subm, instr, vmove_r, _setwant, _clampcur, _sethcur, _lstart, _mode, _vstart
    EXTERN _shift, _casechg, _yankrange, _regstore, _keepinvariant, _tdel, _ylin, _ylen, _ynl, _reg
    EXTERN ldcur, stP, ldP, stQ, ldQ, stp, inc32, dec32, isnone, cmpm, mv_P, mv_Q, mv_n, mv_dn
    EXTERN lmn1, para_r, ew1, bw1, sf_l, nv_c, endlen, pusha, addm, cursub, tabjp
    EXTERN _lstartc, _lendc, _lend, _tgetc, _cls, _nextword, _firstnb
    EXTERN _cur, _gs, _ge, _glin, _bigw, _lastfc, _findch, _matchpos, _tx_len, _tx_nthline

op_go:
    ld (gr_n),hl
    ld (gr_has),a
    ld (gr_k),de
    call get_range
    ret z
    ld a,(gr_op)
    jr opa

; void op_apply(u8 op) : run the operator on [gs, ge) (glin = whole lines).  'v' = select the range (visual text object).
_op_apply:
    ld hl,2
    add hl,sp
    ld a,(hl)
opa:
    ld (oa_op),a
    ld hl,_gs
    ld de,_ge
    call cmpm
    jr c,oa1
    ld a,(oa_op)                ; an empty range: only c does something (it enters insert mode)
    cp 'c'
    ret nz
oa_ins:
    call oa_cs
    ld a,1
    ld (_mode),a
    ret
oa_cs:                          ; cur = gs
    ld hl,(_gs)
    ld de,(_gs+2)
    jp stcur
oa1:
    ld a,(oa_op)
    cp 'v'
    jr nz,oa2
    ld hl,(_gs)
    ld (_vstart),hl
    ld hl,(_gs+2)
    ld (_vstart+2),hl
    ld hl,(_ge)
    ld de,(_ge+2)
    call dec32
    call stcur
    jp _setwant
oa2:
    cp '>'
    jr z,oa_sh
    cp '<'
    jr nz,oa3
oa_sh:
    ld l,a
    ld h,0
    jp _shift
oa3:
    ld hl,oa_case
    call instr
    jr nz,oa4
    ld hl,(_gs+2)               ; gu gU g~
    push hl
    ld hl,(_gs)
    push hl
    ld hl,(_ge+2)
    push hl
    ld hl,(_ge)
    push hl
    call pusha
    call _casechg
    pop bc
    pop bc
    pop bc
    pop bc
    pop bc
    ld a,(_glin)
    or a
    call z,oa_cs
    jp _clampcur
oa4:
    call _yankrange
    ld a,(_glin)
    ld (_ylin),a
    ld a,(_reg)
    or a
    jr z,oa5
    ld hl,0                     ; a named register: copy the unnamed one into it
    push hl
    ld hl,(_ylen)
    push hl
    ld a,(_ynl)
    add a,a
    ld hl,_ylin
    or (hl)
    call pusha
    call _regstore
    pop bc
    pop bc
    pop bc
oa5:
    ld a,(oa_op)
    cp 'y'
    jr nz,oa6
    ld a,(_glin)
    or a
    jp z,oa_cs
    call _lstartc
    call stQ
    ld hl,_gs
    ld de,mv_Q
    call cmpm
    ret nc
    jp oa_cs
oa6:
    cp 'd'
    jr nz,oa7
    ld hl,_ge
    call oa_del
    call _keepinvariant
    ld a,(_glin)
    or a
    jr nz,oa6a
    ld hl,(_gs)
    ld de,(_gs+2)
    jp _sethcur
oa6a:
    call _tx_len
    call stQ
    ld hl,_gs
    ld de,mv_Q
    call cmpm
    jr c,oa6b
    call ldQ                    ; the last lines went: land on the new last line
    call dec32
    call _lstart
    call stS
oa6b:
    call oa_cs
    call _clampcur
    call _lstartc
    call stcur
    ld hl,0                     ; vmove(0, 1): back to the wanted column
    ld (mv_n),hl
    ld a,1
    ld (mv_dn),a
    jp vmove_r
oa7:                            ; c: delete (keeping the line break of whole lines), then insert
    ld hl,(_ge)
    ld de,(_ge+2)
    ld a,(_glin)
    or a
    call nz,dec32
    call stP
    ld hl,mv_P
    call oa_del
    jp oa_ins
; HL -> end position: tdel(gs, end - gs) if end > gs
oa_del:
    ld de,_gs
    call subm
    ret c
    ld a,h
    or l
    or d
    or e
    ret z
    call stQ
    ld hl,(_gs+2)
    push hl
    ld hl,(_gs)
    push hl
    ld hl,(mv_Q+2)
    push hl
    ld hl,(mv_Q)
    push hl
    call _tdel
    pop bc
    pop bc
    pop bc
    pop bc
    ret
oa_case: defm "uU~"
    defb 0

stS:
    ld (_gs),hl
    ld (_gs+2),de
    ret
stE:
    ld (_ge),hl
    ld (_ge+2),de
    ret
; HL = min(count, HL)
minn16:
    ld bc,(gr_n)
    or a
    sbc hl,bc
    add hl,bc
    ret c
    ld h,b
    ld l,c
    ret
; DEHL = lmoven(lstartc(), count, A); Z if there are not that many lines
glmn:
    ld hl,(gr_n)
glmn1:
    ld (mv_dn),a
    ld (mv_n),hl
    call _lstartc
    call lmn1
    jp isnone

; -> NZ (A = 1) with the range set, or Z if the motion fails
get_range:
    xor a
    ld (_glin),a
    call ldcur
    call stS
    call stE
    ld a,(gr_k)
    cp 'W'
    jr z,gr_big
    cp 'B'
    jr z,gr_big
    cp 'E'
    jr nz,gr1
gr_big:
    add a,32
    ld (gr_k),a
    ld a,1
    ld (_bigw),a
    call gr1
    push af
    xor a
    ld (_bigw),a
    pop af
    ret
gr1:
    ld a,(gr_k)
    ld hl,gr_tab
    jp tabjp

g_w:
    ld a,(gr_op)
    cp 'c'
    jr nz,gw2
    call _tgetc
    call _cls
    ld a,l
    or a
    jr z,gw2
    ld (nv_c),a                 ; cw on a word: to the end of the word(s), not to the next one
    call ldcur
    call inc32
    call stp
    call endlen
    call sf_l
    call dec32
    call stp
    ld bc,(gr_n)
    dec bc
    ld a,b
    or c
    jr z,gw1
    ld (mv_n),bc
    call ew1
gw1:
    call inc32
    jp gr_setE
gw2:
    call ldcur
    call stP
    ld hl,(gr_n)
    ld (gr_i),hl
gw3:
    ld hl,(gr_i)
    ld a,h
    or l
    jr z,gw5
    dec hl
    ld (gr_i),hl
    call ldP
    call _nextword
    call stQ
    ld hl,(gr_i)
    ld a,h
    or l
    jr nz,gw4
    call ldP                    ; the last word: stop at the end of its line
    call _lend
    call stP
    ld hl,mv_P
    ld de,mv_Q
    call cmpm
    jr c,gw3
gw4:
    call ldQ
    call stP
    jr gw3
gw5:
    call ldP
    jp gr_setE

g_f:                            ; f F t T
    call pusha
    ld a,(_lastfc)
    call pusha
    ld hl,(gr_n)
    push hl
    call _findch
    pop bc
    pop bc
    pop bc
    ld a,h
    and l
    inc a
    ret z
    ld a,(gr_k)
    cp 'Z'+1
    jr c,gf1
    inc hl
    ld de,_cur
    call addm
    jp gr_setE
gf1:
    call cursub
    jp gr_setS

g_pct:                          ; %
    call _matchpos
    call isnone
    ret z
    call stP
    ld hl,mv_P
    ld de,_cur
    call cmpm
    call ldP
    jr c,gp1
    call inc32
    jp gr_setE
gp1:
    call stS
    call ldcur
    call inc32
    jp gr_setE

g_parf:                         ; }
    ld a,1
    call gpara
    jp gr_setE
g_parb:                         ; {
    xor a
    call gpara
    jp gr_setS
gpara:
    ld (mv_dn),a
    ld hl,(gr_n)
    ld (mv_n),hl
    jp para_r

g_e:
    call ldcur
    call stp
    ld hl,(gr_n)
    ld (mv_n),hl
    call ew1
    call inc32
    jr gr_setE
g_b:
    call ldcur
    call stp
    ld hl,(gr_n)
    ld (mv_n),hl
    call bw1
    jr gr_setS
g_dol:                          ; $
    ld hl,(gr_n)
    dec hl
    ld a,1
    call glmn1
    ret z
    call _lend
    jr gr_setE
g_hat:                          ; ^
    call _lstartc
    call _firstnb
    call stQ
    ld hl,mv_Q
    ld de,_cur
    call cmpm
    call ldQ
    jr c,gr_setS
    jr gr_setE
g_h:                            ; h Left BS
    call _lstartc
    ex de,hl
    ld hl,(_cur)
    or a
    sbc hl,de
    call minn16
    call cursub
    jr gr_setS
g_0:
    call _lstartc
gr_setS:
    call stS
    jr gr_ok
g_l:                            ; l Right Space
    call _lendc
    ld de,(_cur)
    or a
    sbc hl,de
    call minn16
    ld de,_cur
    call addm
gr_setE:
    call stE
gr_ok:
    ld a,1
    or a
    ret
g_j:                            ; j Down + Enter
    ld a,1
    call glmn
    ret z
    call _lend
    call inc32
    call stE
    call _lstartc
    call stS
    jr gr_lin
g_k:                            ; k Up -
    xor a
    call glmn
    ret z
    call stS
    call _lendc
    call inc32
    call stE
gr_lin:
    ld a,1
    ld (_glin),a
    jr gr_ok
g_G:                            ; G and gg (80h)
    ld hl,(gr_n)
    ld de,0
    ld a,(gr_has)
    or a
    jr nz,gG1
    ld hl,1
    ld a,(gr_k)
    cp 'G'
    jr nz,gG1
    ld hl,0FFFFh
    ld d,h
    ld e,l
gG1:
    push de
    push hl
    call _tx_nthline
    pop bc
    pop bc
    call stP
    call _lstartc
    call stQ
    ld hl,mv_P
    ld de,mv_Q
    call cmpm
    jr c,gG2
    call ldQ
    call stS
    call ldP
    jr gG3
gG2:
    call ldP
    call stS
    call ldQ
gG3:
    call _lend
    call inc32
    call stE
    jr gr_lin
g_def:                          ; dd yy cc >> << ... (the operator key again), anything else is not a motion
    ld hl,gr_op
    cp (hl)
    jr z,gd0
    xor a
    ret
gd0:
    call _lstartc
    call stS
    call stE
    ld hl,(gr_n)
    ld (gr_i),hl
gd1:
    ld hl,(gr_i)
    ld a,h
    or l
    jr z,gr_lin
    dec hl
    ld (gr_i),hl
    call _tx_len
    call stQ
    ld hl,_ge
    ld de,mv_Q
    call cmpm
    jp nc,gr_lin
    ld hl,(_ge)
    ld de,(_ge+2)
    call _lend
    call inc32
    call stE
    jr gd1

gr_tab:
    defb 'w'
    defw g_w
    defb 'e'
    defw g_e
    defb 'b'
    defw g_b
    defb '$'
    defw g_dol
    defb 'j'
    defw g_j
    defb 1Fh
    defw g_j
    defb '+'
    defw g_j
    defb 0Dh
    defw g_j
    defb 'k'
    defw g_k
    defb 1Eh
    defw g_k
    defb '-'
    defw g_k
    defb 'h'
    defw g_h
    defb 1Dh
    defw g_h
    defb 08h
    defw g_h
    defb 'l'
    defw g_l
    defb 1Ch
    defw g_l
    defb ' '
    defw g_l
    defb 'f'
    defw g_f
    defb 'F'
    defw g_f
    defb 't'
    defw g_f
    defb 'T'
    defw g_f
    defb '%'
    defw g_pct
    defb '}'
    defw g_parf
    defb '{'
    defw g_parb
    defb '0'
    defw g_0
    defb '^'
    defw g_hat
    defb 'G'
    defw g_G
    defb 80h
    defw g_G
    defb 0
    defw g_def

    SECTION bss_user
gr_n:   defs 2
gr_i:   defs 2
gr_k:   defb 0                  ; motion key   } stored together from DE
gr_op:  defb 0                  ; operator     }
gr_has: defb 0
oa_op:  defb 0
