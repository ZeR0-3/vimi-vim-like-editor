; normal_z80.asm - normal-mode command keys (the asm twin of the switch at the end of normal_key in core/ed_normal.c; -DM_ASM)
;   void nkey(u8 k) fastcall : one command key with no operator pending.  The count is in nk_n, nk_has says whether one was typed.
; Positions: DE = high word, HL = low word.  Helpers and scratch (mv_P mv_Q mv_n mv_dn nv_p) come from nav_z80.asm.
    SECTION code_user
    PUBLIC _nkey, _firstnb, pusha, addm, cursub, tabjp, subm, instr, pop2
    EXTERN op_go
    EXTERN ldcur, stcur, stP, ldP, stQ, ldQ, stp, inc32, dec32, isnone, cmpm, mv_P, mv_Q, mv_n, mv_dn
    EXTERN lmn1, para_r, vmove_r, ew1
    EXTERN _lstartc, _lendc, _lend, _tgetc, _sethcur, _gotoline, _wordfwd, _wordback
    EXTERN _cur, _want, _mode, _mk, _bigw, _nk_n, _nk_has
    EXTERN _pend, _pcount, _lastfc, _lastlen, _replay, _ri, _rmode, _vstart, _vline, _vblk, _sback, _cmdch, _cmdlen
    EXTERN _tx_get, _findch, _scroll_view, _cmd_x, _case_toggle, _cmd_join, _cmd_paste, _cmd_undo
    EXTERN gind_r
    EXTERN _begin_ins, _pind, _tins, _screen_line, _matchpos, _star, _dosearch

_nkey:
    ld a,l
    ld (nk_k),a
nk_disp:                        ; A = key: jump to its handler (with A = key), or just return
    ld hl,nk_tab
; A = key, HL -> table of (key byte, handler word) ..., 0, default handler: jump to the handler with A = key
tabjp:
    ld c,a
tj1:
    ld a,(hl)
    inc hl
    or a
    jr z,tj2
    cp c
    jr z,tj2
    inc hl
    inc hl
    jr tj1
tj2:
    ld a,(hl)
    inc hl
    ld h,(hl)
    ld l,a
    ld a,c
    jp (hl)

; ---- small helpers
pusha:                          ; push A as a 16-bit argument (keeps DE)
    pop hl
    ld c,a
    ld b,0
    push bc
    jp (hl)
keq:                            ; A = (key == A) ? 1 : 0
    ld hl,nk_k
    cp (hl)
    ld a,1
    ret z
    dec a
    ret
setjp:                          ; jprev = cur  (mk[26]); keeps A
    call ldcur
    ld (_mk+104),hl
    ld (_mk+106),de
    ret
; DEHL = (HL) - (DE), 4 bytes each; C = borrow
subm:
    ld c,(hl)
    inc hl
    ld b,(hl)
    inc hl
    push hl
    ex de,hl
    ld e,(hl)
    inc hl
    ld d,(hl)
    inc hl
    push hl
    ld h,b
    ld l,c
    or a
    sbc hl,de
    ex (sp),hl
    ld e,(hl)
    inc hl
    ld d,(hl)
    pop bc
    pop hl
    ld a,(hl)
    inc hl
    ld h,(hl)
    ld l,a
    sbc hl,de
    ex de,hl
    ld h,b
    ld l,c
    ret
; HL = min(count, DEHL)
minn:
    ld a,d
    or e
    jr nz,mn1
    ld bc,(_nk_n)
    sbc hl,bc
    add hl,bc
    ret c
mn1:
    ld hl,(_nk_n)
    ret
; DEHL = cur - HL
cursub:
    ex de,hl
    ld hl,(_cur)
    or a
    sbc hl,de
    ex de,hl
    ld hl,(_cur+2)
    jr nc,cs1
    dec hl
cs1:
    ex de,hl
    ret
; DEHL = (DE) + HL
addm:
    ex de,hl
    ld c,(hl)
    inc hl
    ld b,(hl)
    inc hl
    ld a,(hl)
    inc hl
    ld h,(hl)
    ld l,a
    ex de,hl
    add hl,bc
    ret nc
    inc de
    ret
; HL = HL * A
mula:
    ex de,hl
    ld hl,0
    ld b,8
ml1:
    add hl,hl
    rlca
    jr nc,ml2
    add hl,de
ml2:
    djnz ml1
    ret
; pos_t firstnb(pos_t ls) fastcall : first non-blank of the line starting at ls (a line always ends with LF, which stops the scan)
_firstnb:
    call stP
fn1:
    call ldP
    push de
    push hl
    call _tx_get
    pop bc
    pop bc
    ld a,l
    cp ' '
    jr z,fn2
    cp 9
    jp nz,ldP
fn2:
    call ldP
    call inc32
    call stP
    jr fn1

; ---- the keys
h_h:                            ; h Left BS
    call _lstartc
    call stP
    ld hl,_cur
    ld de,mv_P
    call subm                   ; column
    call minn
    call cursub
    jp _sethcur
h_bar:                          ; |
    ld hl,(_nk_n)
    dec hl
    ld (_nk_n),hl
    call _lstartc
    call stQ
    call _lendc
    call stP
    ld de,mv_Q
    jr hl2
h_l:                            ; l Right Space
    call _lendc
    call stP
    ld de,_cur
hl2:                            ; mv_P = line end, DE -> base: sethcur(base + min(count, room))
    push de
    ld hl,mv_P
    call subm
    jr c,hl0
    ld a,h
    or l
    or d
    or e
    jr z,hl0
    call dec32
    jr hl1
hl0:
    ld hl,0
    ld d,h
    ld e,l
hl1:
    call minn
    pop de
    call addm
    jp _sethcur
h_f:                            ; f F t T (the target character is in lastfc)
    call pusha
    ld a,(_lastfc)
    call pusha
    ld hl,(_nk_n)
    push hl
    call _findch
    pop bc
    pop bc
    pop bc
    ld a,h
    and l
    inc a
    ret z
    ld a,(nk_k)
    cp 'Z'+1
    jr c,hf1
    ld de,_cur
    call addm
    jp _sethcur
hf1:
    call cursub
    jp _sethcur
h_j:
    ld a,1
    jr vmv
h_k:
    xor a
vmv:
    ld hl,(_nk_n)
vmv_hl:
    ld (mv_n),hl
    ld (mv_dn),a
    jp vmove_r
h_plus:                         ; + Enter
    ld a,1
    jr hm1
h_minus:
    xor a
hm1:
    call vmv
h_hat:                          ; ^
    call _lstartc
    call _firstnb
    jp _sethcur
h_0:
    call _lstartc
    jp _sethcur
h_dol:                          ; $
    ld hl,(_nk_n)
    dec hl
    ld (mv_n),hl
    ld a,1
    ld (mv_dn),a
    call _lstartc
    call lmn1
    call isnone
    ret z
    call stP
    call _lend
    call stQ
    ld hl,mv_P
    ld de,mv_Q
    call cmpm
    call ldQ
    call c,dec32
    call _sethcur
    ld hl,7FFFh
    ld (_want),hl
    ret
h_par:                          ; { }
    call setjp
    ld hl,(_nk_n)
    ld (mv_n),hl
    sub '{'
    ld (mv_dn),a
    call para_r
    jp _sethcur
h_w:
    ld hl,(_nk_n)
    jp _wordfwd
h_b:
    ld hl,(_nk_n)
    jp _wordback
h_e:
    call ldcur
    call stp
    ld hl,(_nk_n)
    ld (mv_n),hl
    call ew1
    jp _sethcur
h_big:                          ; W B E
    ld a,1
    ld (_bigw),a
    ld a,(nk_k)
    or 20h
    call nk_disp
    xor a
    ld (_bigw),a
    ret
h_half:                         ; Ctrl-D Ctrl-U
    ld hl,1
    ld a,(_nk_has)
    or a
    jr z,hh1
    ld hl,(_nk_n)
hh1:
    ld a,12
    call mula
    ld a,4
    jr hpg
h_page:                         ; Ctrl-F Ctrl-B
    ld hl,(_nk_n)
    ld a,22
    call mula
    ld a,6
hpg:
    push hl
    call keq
    pop hl
    call vmv_hl
    call ldcur
    jp _sethcur
h_scr:                          ; Ctrl-E Ctrl-Y
    ld hl,(_nk_n)
    push hl
    ld a,5
    call keq
    call pusha
    call _scroll_view
pop2:
    pop bc
    pop bc
nk_ret:
    ret
h_G:
    call setjp
    ld a,(_nk_has)
    or a
    ld hl,(_nk_n)
    ld de,0
    jp nz,_gotoline
    dec de
    ld h,d
    ld l,e
    jp _gotoline
h_x:
    ld hl,(_nk_n)
    jp _cmd_x
h_X:
    ld de,'d'*256+'h'
    jr opm
h_D:
    ld de,'d'*256+'$'
    jr opm
h_C:
    ld de,'c'*256+'$'
    jr opm
h_s:
    ld de,'c'*256+'l'
    jr opm
h_S:
    ld de,'c'*256+'c'
    jr opm
h_Y:
    ld de,'y'*256+'y'
opm:                            ; operator D with motion E
    ld hl,(_nk_n)
    ld a,(_nk_has)
    jp op_go
h_til:
    ld hl,(_nk_n)
    jp _case_toggle
h_J:
    ld hl,(_nk_n)
    push hl
    ld a,1
    call pusha
    call _cmd_join
    jr pop2
h_p:                            ; p P
    ld a,'P'
    call keq
    call pusha
    ld hl,(_nk_n)
    push hl
    call _cmd_paste
    jr pop2
h_u:                            ; u Ctrl-R
    ld a,12h
    call keq
    ld l,a
    ld h,0
    jp _cmd_undo
h_dot:
    ld a,(_lastlen)
    or a
    ret z
    ld a,(_replay)
    or a
    ret nz
    ld (_ri),a
    inc a
    ld (_replay),a
    ret
h_a:
    call _tgetc
    ld a,l
    cp 10
    jr z,h_i
    call ldcur
    call inc32
    jr hi1
h_I:
    call _lstartc
    call _firstnb
    jr hi1
h_A:
    call _lendc
hi1:
    call stcur
h_i:                            ; begin_ins(key, count)
    ld a,(nk_k)
    call pusha
    ld hl,(_nk_n)
hi2:
    push hl
    call _begin_ins
    jp pop2
h_R:
    ld a,'i'
    call pusha
    ld hl,1
    push hl
    call _begin_ins
    pop bc
    pop bc
    ld a,1
    ld (_rmode),a
    ret
h_o:
    call _lendc
    call inc32
    jr ho1
h_O:
    call _lstartc
ho1:
    call stP
    call _lstartc
    ld a,32
    call gind_r                 ; remember the indent of the current line (:set ai)
    call ldP
    push de
    push hl
    ld a,10
    call pusha
    call _tins
    pop bc
    pop bc
    pop bc
    ld a,h
    or l
    ret z                       ; no room
    call ldP
    call stcur
    call _pind
    jr h_i
h_pend:                         ; d y c g z > < Z q @ m ' ` : wait for the rest
    ld (_pend),a
    ld hl,0
    ld a,(_nk_has)
    or a
    jr z,hp1
    ld hl,(_nk_n)
hp1:
    ld (_pcount),hl
    ret
h_r:
    ld (_pend),a
    ret
h_v:                            ; v V Ctrl-V
    call ldcur
    ld (_vstart),hl
    ld (_vstart+2),de
    ld a,'V'
    call keq
    ld (_vline),a
    ld a,16h
    call keq
    ld (_vblk),a
    ld a,3
    ld (_mode),a
    ret
h_scl:                          ; H M L
    ld l,a
    ld h,0
    jp _screen_line
h_pct:                          ; %
    call setjp
    call _matchpos
    call isnone
    ret z
    jp _sethcur
h_star:                         ; * #
    call setjp
    ld a,'*'
    call keq
    ld l,a
    ld h,0
    jp _star
h_n:                            ; n N
    call setjp
    ld a,'n'
    call keq
    ld b,a
    ld a,(_sback)
    sub 1
    sbc a,a
    inc a
    xor b
    ld l,a
    ld h,0
    jp _dosearch
h_cmd:                          ; : / ?
    call setjp
    ld (_cmdch),a
    ld a,2
    ld (_mode),a
    xor a
    ld (_cmdlen),a
    ret

nk_tab:
    defb 'h'
    defw h_h
    defb 1Dh
    defw h_h
    defb 08h
    defw h_h
    defb 'l'
    defw h_l
    defb 1Ch
    defw h_l
    defb ' '
    defw h_l
    defb 'j'
    defw h_j
    defb 1Fh
    defw h_j
    defb 'k'
    defw h_k
    defb 1Eh
    defw h_k
    defb 'w'
    defw h_w
    defb 'b'
    defw h_b
    defb 'e'
    defw h_e
    defb 'x'
    defw h_x
    defb 'i'
    defw h_i
    defb 'a'
    defw h_a
    defb 'd'
    defw h_pend
    defb 'y'
    defw h_pend
    defb 'c'
    defw h_pend
    defb 'g'
    defw h_pend
    defb 'z'
    defw h_pend
    defb '>'
    defw h_pend
    defb '<'
    defw h_pend
    defb 'Z'
    defw h_pend
    defb 'q'
    defw h_pend
    defb '@'
    defw h_pend
    defb 'm'
    defw h_pend
    defb 27h
    defw h_pend
    defb '`'
    defw h_pend
    defb 'f'
    defw h_f
    defb 'F'
    defw h_f
    defb 't'
    defw h_f
    defb 'T'
    defw h_f
    defb '+'
    defw h_plus
    defb 0Dh
    defw h_plus
    defb '-'
    defw h_minus
    defb '|'
    defw h_bar
    defb '0'
    defw h_0
    defb '^'
    defw h_hat
    defb '$'
    defw h_dol
    defb '}'
    defw h_par
    defb '{'
    defw h_par
    defb 'W'
    defw h_big
    defb 'B'
    defw h_big
    defb 'E'
    defw h_big
    defb 04h
    defw h_half
    defb 15h
    defw h_half
    defb 06h
    defw h_page
    defb 02h
    defw h_page
    defb 05h
    defw h_scr
    defb 19h
    defw h_scr
    defb 'G'
    defw h_G
    defb 'X'
    defw h_X
    defb 'D'
    defw h_D
    defb 'C'
    defw h_C
    defb 's'
    defw h_s
    defb 'S'
    defw h_S
    defb 'Y'
    defw h_Y
    defb '~'
    defw h_til
    defb 'J'
    defw h_J
    defb 'p'
    defw h_p
    defb 'P'
    defw h_p
    defb 'u'
    defw h_u
    defb 12h
    defw h_u
    defb '.'
    defw h_dot
    defb 'I'
    defw h_I
    defb 'A'
    defw h_A
    defb 'R'
    defw h_R
    defb 'o'
    defw h_o
    defb 'O'
    defw h_O
    defb 'r'
    defw h_r
    defb 'v'
    defw h_v
    defb 'V'
    defw h_v
    defb 16h
    defw h_v
    defb 'H'
    defw h_scl
    defb 'M'
    defw h_scl
    defb 'L'
    defw h_scl
    defb '%'
    defw h_pct
    defb '*'
    defw h_star
    defb '#'
    defw h_star
    defb 'n'
    defw h_n
    defb 'N'
    defw h_n
    defb ':'
    defw h_cmd
    defb '/'
    defw h_cmd
    defb '?'
    defw h_cmd
    defb 0
    defw nk_ret

; ======================================================================================================================
; void normal_key(u8 k) fastcall : one key in normal mode (also the motions of visual mode).
; Handles the f/t target, ; and , the count, the keys that complete a pending prefix (g z q @ Z m ' ` r and the
; operators d y c > < gu gU g~ with their g / text-object / mark forms), then hands plain commands to nk_disp.
    PUBLIC _normal_key
    EXTERN _pf, _lastfk, _count, _pg, _ptob, _top, _mrc, _inmac, _mlast, _mlen, _mb, _rlen, _roff, _mc, _mi
    EXTERN _modified, _quitf, _glin, _gs, _ge, _setmsg, _dosave, _textobj, _op_apply, _tdel, _tx_aux_get, _tx_len
    EXTERN _lstart, _lmoven, ld32, l_mult
    defc RBASE = 2048           ; YSZ + 2 * UD (core/ed_reg.c)
    defc MACB = 80

; A = character, HL -> 0-terminated list: Z if A is in it.  Keeps A and C.
instr:
    ld b,a
is1:
    ld a,(hl)
    or a
    jr z,is2
    cp b
    ret z
    inc hl
    jr is1
is2:
    inc a
    ld a,b
    ret
s_pnm:  defm "rgzm'`q@"
    defb 0
s_ops:  defm "dycuU~"
    defb 0
s_tob:  defm "ia'`"
    defb 0
s_case: defm "uU~"
s_empty: defb 0
s_nomark: defm "mark not set"
    defb 0

_normal_key:
    ld c,l                      ; C = key
    ld a,(_pf)
    or a
    jr z,n1
    ld b,a                      ; the character after f F t T
    xor a
    ld (_pf),a
    ld a,c
    cp 1Bh
    ret z
    ld (_lastfc),a
    ld a,b
    ld (_lastfk),a
    ld c,a
    jr n3
n1:
    ld a,(_pend)
    ld hl,s_pnm
    call instr
    jr z,n3                     ; the next key is an argument (r g z m ' ` q @), not f or ;
    ld a,(_lastfk)
    or a
    jr z,n2
    ld b,a
    ld a,c
    cp ';'
    jr nz,n1a
    ld c,b
    jr n3
n1a:
    cp ','
    jr nz,n2
    ld a,b
    xor 20h
    ld c,a
    jr n3
n2:
    ld a,c
    or 20h
    cp 'f'
    jr z,n2a
    cp 't'
    jr nz,n3
n2a:
    ld a,c
    ld (_pf),a
    ret
n3:
    ld a,c
    ld (nk_k),a
    ld a,(_pend)
    cp 'r'
    jr z,n5
    ld a,c                      ; the count
    cp '0'
    jr c,n5
    cp '9'+1
    jr nc,n5
    sub '0'
    ld hl,(_count)
    jr nz,n4
    ld b,a
    ld a,h
    or l
    jr z,n5                     ; a 0 with no count is the command 0
    ld a,b
n4:
    ld de,1000
    or a
    sbc hl,de
    add hl,de
    jr nc,n4a                   ; >= 1000: the result would pass 9999
    ld e,a
    push de
    ld a,10
    call mula
    pop de
    ld d,0
    add hl,de
    jr n4b
n4a:
    ld hl,9999
n4b:
    ld (_count),hl
    ret
n5:
    ld a,(_pend)                ; after d y c gu gU g~ : g, or i a ' ` + object / mark
    ld hl,s_ops
    call instr
    jr nz,n6
    ld a,(_pg)
    ld hl,_ptob
    or (hl)
    jr nz,n6
    ld a,c
    cp 'g'
    jr nz,n5a
    ld a,1
    ld (_pg),a
    ret
n5a:
    ld hl,s_tob
    call instr
    jr nz,n6
    ld (_ptob),a
    ret
n6:
    ld hl,(_count)              ; HL = count or 1, B = a count was typed
    ld b,0
    ld a,h
    or l
    jr z,n6a
    inc b
    jr n6b
n6a:
    inc hl
n6b:
    ld de,0
    ld (_count),de
    ld a,(_pend)
    or a
    jr nz,n7
    ld (_nk_n),hl
    ld a,b
    ld (_nk_has),a
    ld a,c
    jp nk_disp
n7:
    ld (nk_p),a
    xor a
    ld (_pend),a
    ld de,(_pcount)             ; the count typed before the prefix multiplies
    ld a,d
    or e
    jr z,n7a
    call l_mult
    ld b,1
n7a:
    ld (_nk_n),hl
    ld a,b
    ld (_nk_has),a
    ld hl,0
    ld (_pcount),hl
    ld a,(nk_p)
    cp 'g'
    jr z,p_g
    cp 'z'
    jp z,p_z
    cp 'q'
    jp z,p_q
    cp '@'
    jp z,p_q
    cp 'Z'
    jp z,p_Z
    cp 'r'
    jp z,p_r
    cp 'm'
    jp z,p_m
    cp 27h
    jp z,p_m
    cp '`'
    jp z,p_m
    ld a,(_ptob)
    or a
    jp nz,p_tob
    ld a,(_pg)
    or a
    jr z,p_op
    xor a
    ld (_pg),a
    ld a,(nk_k)
    cp 'g'
    jr nz,p_op1
    ld e,80h                    ; dgg ygg ...
    jr p_op2
p_op1:
    ld hl,nk_p
    cp (hl)
    ret nz
p_op:
    ld a,(nk_k)
    ld e,a
p_op2:
    ld a,(nk_p)
    ld d,a
    jp opm

p_g:                            ; gg gJ gu gU g~
    ld a,(nk_k)
    cp 'g'
    jr nz,pg2
    call setjp
    ld a,(_nk_has)
    or a
    ld hl,(_nk_n)
    jr nz,pg1
    ld hl,1
pg1:
    ld de,0
    jp _gotoline
pg2:
    cp 'J'
    jr nz,pg3
    ld hl,(_nk_n)
    push hl
    xor a
    call pusha
    call _cmd_join
    jp pop2
pg3:
    ld hl,s_case
    call instr
    ret nz
    jp h_pend

p_z:                            ; zt zz zb  z<CR> z. z- : the cursor line to the top / middle / bottom
    ld a,(nk_k)
    ld hl,0
    cp 't'
    jr z,pz1
    cp 0Dh
    jr z,pz1
    ld l,23
    cp 'b'
    jr z,pz1
    cp '-'
    jr z,pz1
    ld l,12
pz1:
    ld (mv_n),hl
    xor a
    ld (mv_dn),a
    call _lstartc
    call lmn1
    call isnone
    jr nz,pz2
    ld hl,0
    ld d,h
    ld e,l
pz2:
    ld (_top),hl
    ld (_top+2),de
    ret

p_q:                            ; qa (qA appends) ... q : record;  @a @@ : play
    ld a,(_mrc)
    ld hl,_inmac
    or (hl)
    ret nz
    ld a,(nk_k)
    ld c,a
    ld a,(nk_p)
    cp '@'
    jr nz,pq_rec
    ld a,c
    cp '@'
    jr nz,pq1
    ld a,(_mlast)
    ld c,a
pq1:
    ld a,c
    cp 'a'
    ret c
    cp 'z'+1
    ret nc
    sub 'a'
    add a,a
    ld e,a
    ld d,0
    ld hl,_rlen
    add hl,de
    ld a,(hl)
    inc hl
    ld h,(hl)
    ld l,a
    or h
    ret z                       ; empty register
    ld a,h
    or a
    jr nz,pq2
    ld a,l
    cp MACB+1
    jr c,pq3
pq2:
    ld a,MACB
pq3:
    ld (_mlen),a
    ld a,c
    ld (_mlast),a
    ld hl,_mb
    push hl
    ld hl,_roff
    add hl,de
    ld a,(hl)
    inc hl
    ld h,(hl)
    ld l,a
    ld de,RBASE
    add hl,de
    push hl
    ld a,(_mlen)
    call pusha
    call _tx_aux_get
    pop bc
    pop bc
    pop bc
    ld a,1
    ld (_inmac),a
    ld hl,(_nk_n)
    ld (_mc),hl
    xor a
    ld (_mi),a                  ; ed_key feeds the keys once this key is done
    ret
pq_rec:
    ld a,c
    or 20h
    cp 'a'
    ret c
    cp 'z'+1
    ret nc
    ld a,c
    ld (_mrc),a
    xor a
    ld (_mlen),a
    ret

p_Z:                            ; ZZ
    ld a,(nk_k)
    cp 'Z'
    ret nz
    ld a,(_modified)
    or a
    jr z,pZ1
    ld hl,s_empty
    push hl
    call _dosave
    pop bc
pZ1:
    ld a,(_modified)
    or a
    ret nz
    inc a
    ld (_quitf),a
    ret

p_r:                            ; r + character
    ld a,(nk_k)
    cp 20h
    ret c
    call _tgetc
    ld a,l
    cp 10
    ret z
    call ldcur
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
    call ldcur
    push de
    push hl
    ld a,(nk_k)
    call pusha
    call _tins
    pop bc
    jp pop2

; HL -> mk[key - 'a'] for the key in A; C set if the key is not a..z
mkptr:
    cp 'a'
    ret c
    cp 'z'+1
    ccf
    ret c
    sub 'a'
    add a,a
    add a,a
    ld e,a
    ld d,0
    ld hl,_mk
    add hl,de
    or a
    ret

p_m:                            ; ma  'a `a  '' ``
    ld a,(nk_k)
    ld c,a
    ld a,(nk_p)
    cp 'm'
    jr z,pm1
    ld a,c
    cp 27h
    jr z,pm0
    cp '`'
    jr nz,pm1
pm0:
    ld hl,_mk+104               ; jprev
    jr pm2
pm1:
    ld a,c
    call mkptr
    ret c
    ld a,(nk_p)
    cp 'm'
    jr nz,pm2
    ex de,hl
    ld hl,_cur
    ld bc,4
    ldir
    ret
pm2:
    call ld32
    call stP                    ; the target
    call isnone
    jr nz,pm3
    ld hl,s_nomark
    push hl
    call _setmsg
    pop bc
    ret
pm3:
    call setjp
    call _tx_len
    call stQ
    ld hl,mv_P
    ld de,mv_Q
    call cmpm
    jr c,pm4
    call ldQ
    call dec32
    call stP
pm4:
    call ldP
    ld a,(nk_p)
    cp '`'
    jp z,_sethcur
    call _lstart
    call _firstnb
    jp _sethcur

p_tob:                          ; operator + i/a + object, or operator + ' ` + mark
    ld (nk_t),a
    xor a
    ld (_ptob),a
    ld (_pg),a
    ld a,(nk_t)
    cp 27h
    jr z,pt1
    cp '`'
    jr z,pt1
    ld a,(nk_p)
    call pusha
    ld a,(nk_t)
    call pusha
    ld a,(nk_k)
    call pusha
    call _textobj
    pop bc
    jp pop2
pt1:
    ld a,(nk_k)
    call mkptr
    ret c
    call ld32
    call isnone
    ret z
    call stP
    ld hl,mv_P
    ld de,_cur
    call cmpm
    jr c,pt2
    call ldcur
    ld (_gs),hl
    ld (_gs+2),de
    call ldP
    jr pt3
pt2:
    call ldP
    ld (_gs),hl
    ld (_gs+2),de
    call ldcur
pt3:
    ld (_ge),hl
    ld (_ge+2),de
    ld a,(nk_t)
    cp 27h
    ld a,0
    jr nz,pt4
    ld hl,(_gs)
    ld de,(_gs+2)
    call _lstart
    ld (_gs),hl
    ld (_gs+2),de
    ld hl,(_ge)
    ld de,(_ge+2)
    call _lend
    call inc32
    ld (_ge),hl
    ld (_ge+2),de
    ld a,1
pt4:
    ld (_glin),a
    ld a,(nk_p)
    call pusha
    call _op_apply
    pop bc
    ret

    SECTION bss_user
nk_k:   defb 0
nk_p:   defb 0
nk_t:   defb 0
