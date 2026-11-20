; nav_z80.asm - word-class scanning primitives for the editor (the char-by-char loops of w b e W B E)
;   pos_t skipf(pos_t p, pos_t end, u8 c) : while (p < end && cls(tget(p)) == c) p++;  return p;
;   pos_t skipb(pos_t p, u8 c, u8 o)      : while (p > 0 && cls(tget(p - o)) == c) p--; return p;   (o = 0 or 1)
;   cls(): 0 blank (space, LF, TAB), 1 word char (digit, letter, '_', >= A0h; any non-blank when bigw), 2 punctuation
    SECTION code_user
    PUBLIC _skipf, _skipb, _matchb, _casebuf, _tobj
    EXTERN _tx_get, _bigw, _gs, _ge

; A = char -> A = class
nv_cls:
    cp ' '
    jr z,nc0
    cp 10
    jr z,nc0
    cp 9
    jr z,nc0
    ld b,a
    ld a,(_bigw)
    or a
    ld a,b
    jr nz,nc1
    cp '0'
    jr c,nc2
    cp '9'+1
    jr c,nc1
    cp 'A'
    jr c,nc2
    cp 'Z'+1
    jr c,nc1
    cp '_'
    jr z,nc1
    cp 'a'
    jr c,nc2
    cp 'z'+1
    jr c,nc1
    cp 0A0h
    jr nc,nc1
nc2:
    ld a,2
    ret
nc1:
    ld a,1
    ret
nc0:
    xor a
    ret

; class of the byte at DE:HL (hi:lo) -> A, compared with nv_c -> Z if equal
nv_test:
    push de
    push hl
    call _tx_get
    pop af
    pop af
    ld a,l
    call nv_cls
    ld hl,nv_c
    cp (hl)
    ret

_skipf:
    ld hl,2
    add hl,sp
    ld a,(hl)
    ld (nv_c),a
    ld hl,4
    add hl,sp
    ld de,nv_end
    ld bc,4
    ldir
    ld hl,8
    add hl,sp
    ld de,nv_p
    ld bc,4
    ldir
sf_l:
    ld hl,(nv_p)
    ld de,(nv_end)
    or a
    sbc hl,de
    ld hl,(nv_p+2)
    ld de,(nv_end+2)
    sbc hl,de
    jr nc,sf_d
    ld de,(nv_p+2)
    ld hl,(nv_p)
    call nv_test
    jr nz,sf_d
    ld hl,(nv_p)
    inc hl
    ld (nv_p),hl
    ld a,h
    or l
    jr nz,sf_l
    ld hl,(nv_p+2)
    inc hl
    ld (nv_p+2),hl
    jr sf_l
sf_d:
    ld hl,(nv_p)
    ld de,(nv_p+2)
    ret

_skipb:
    ld hl,2
    add hl,sp
    ld a,(hl)
    ld (nv_o),a
    inc hl
    inc hl
    ld a,(hl)
    ld (nv_c),a
    inc hl
    inc hl
    ld de,nv_p
    ld bc,4
    ldir
sb_l:
    ld hl,(nv_p)
    ld de,(nv_p+2)
    ld a,h
    or l
    or d
    or e
    jr z,sb_d              ; p == 0
    ld a,(nv_o)
    or a
    jr z,sb_g
    ld a,h
    or l
    dec hl
    jr nz,sb_g
    dec de
sb_g:
    call nv_test
    jr nz,sb_d
    ld hl,(nv_p)
    ld a,h
    or l
    dec hl
    ld (nv_p),hl
    jr nz,sb_l
    ld hl,(nv_p+2)
    dec hl
    ld (nv_p+2),hl
    jr sb_l
sb_d:
    ld hl,(nv_p)
    ld de,(nv_p+2)
    ret

; pos_t matchb(pos_t cur, pos_t le, pos_t len)   -- % : first bracket ( ) [ ] { } in [cur,le), then its partner (nesting counted),
;   searching on to the end of the text (opening bracket) or back to 0 (closing bracket); POS_NONE if there is none
_matchb:
    ld hl,2
    add hl,sp
    ld de,nv_len
    ld bc,4
    ldir
    ld de,nv_end
    ld bc,4
    ldir
    ld de,nv_p
    ld bc,4
    ldir
mb_f:                          ; find the first bracket
    ld hl,(nv_p)
    ld de,(nv_end)
    or a
    sbc hl,de
    ld hl,(nv_p+2)
    ld de,(nv_end+2)
    sbc hl,de
    jp nc,mb_none
    ld hl,(nv_p+2)
    push hl
    ld hl,(nv_p)
    push hl
    call _tx_get
    pop af
    pop af
    ld a,l
    ld (nv_c),a
    ld hl,mb_brk
    ld bc,6
    cpir
    jr z,mb_got
    ld hl,(nv_p)
    inc hl
    ld (nv_p),hl
    ld a,h
    or l
    jr nz,mb_f
    ld hl,(nv_p+2)
    inc hl
    ld (nv_p+2),hl
    jr mb_f
mb_got:
    ld a,c
    cpl
    add a,6                    ; k = 5 - BC
    ld (nv_o),a                ; k
    xor 1
    ld e,a
    ld d,0
    ld hl,mb_brk
    add hl,de
    ld a,(hl)
    ld (nv_m),a
    xor a
    ld (nv_d),a
mb_l:
    ld hl,(nv_p+2)
    push hl
    ld hl,(nv_p)
    push hl
    call _tx_get
    pop af
    pop af
    ld a,(nv_c)
    ld c,a
    ld a,l
    cp c
    jr nz,mb_nc
    ld hl,nv_d
    inc (hl)
    jr mb_adv
mb_nc:
    ld hl,nv_m
    cp (hl)
    jr nz,mb_adv
    ld hl,nv_d
    dec (hl)
    jr z,mb_hit
mb_adv:
    ld a,(nv_o)
    rrca
    jr c,mb_bk
    ld hl,(nv_p)               ; forward
    inc hl
    ld (nv_p),hl
    ld a,h
    or l
    jr nz,mb_fw
    ld hl,(nv_p+2)
    inc hl
    ld (nv_p+2),hl
mb_fw:
    ld hl,(nv_p)
    ld de,(nv_len)
    or a
    sbc hl,de
    ld hl,(nv_p+2)
    ld de,(nv_len+2)
    sbc hl,de
    jr c,mb_l
    jp mb_none
mb_bk:
    ld hl,(nv_p)
    ld de,(nv_p+2)
    ld a,h
    or l
    or d
    or e
    jp z,mb_none
    ld a,h
    or l
    dec hl
    ld (nv_p),hl
    jr nz,mb_l
    dec de
    ld (nv_p+2),de
    jr mb_l
mb_hit:
    ld hl,(nv_p)
    ld de,(nv_p+2)
    ret
mb_none:
    ld hl,0FFFFh
    ld d,h
    ld e,l
    ret
mb_brk: defm "()[]{}"

; ======================================================================================================================
; Cursor helpers (the asm twin of core/ed_move.c and of lstart/lend in core/ed_undo.c; built with -DM_ASM).
; Positions are 32 bit: DE = high word, HL = low word (the sccz80 long).  "fastcall" = the one argument arrives in DEHL / HL.
; Scratch: mv_P mv_Q (callers), mv_T mv_L (lmv), nv_p nv_end nv_c nv_o (the word scanners above).  No IX, no recursion.
    PUBLIC _lstart, _lend, _lstartc, _lendc, _tgetc, _setwant, _clampcur, _sethcur, _lmove, _lmoven, _para, _vmove
    PUBLIC _nextword, _endword, _backword, _wordfwd, _wordback, _gotoline, _cls
    PUBLIC ldcur, stcur, stP, ldP, stQ, ldQ, stp, inc32, dec32, isnone, cmpm, ld32, mv_P, mv_Q, mv_n, mv_dn, lmn1, para_r, vmove_r, ew1, bw1, sf_l, nv_c, endlen, stL, mv_L, lmv, sb_l, nv_o, nv_end
    EXTERN _tx_len, _tx_find, _tx_rfind, _tx_nthline, _cur, _want, _mode

ldcur:
    ld hl,(_cur)
    ld de,(_cur+2)
    ret
stcur:
    ld (_cur),hl
    ld (_cur+2),de
    ret
stP:
    ld (mv_P),hl
    ld (mv_P+2),de
    ret
ldP:
    ld hl,(mv_P)
    ld de,(mv_P+2)
    ret
stQ:
    ld (mv_Q),hl
    ld (mv_Q+2),de
    ret
ldQ:
    ld hl,(mv_Q)
    ld de,(mv_Q+2)
    ret
stL:
    ld (mv_L),hl
    ld (mv_L+2),de
    ret
stp:
    ld (nv_p),hl
    ld (nv_p+2),de
    ret
inc32:
    inc hl
    ld a,h
    or l
    ret nz
    inc de
    ret
dec32:
    ld a,h
    or l
    dec hl
    ret nz
    dec de
    ret
isnone:                         ; Z if DEHL == POS_NONE
    ld a,h
    and l
    and d
    and e
    inc a
    ret
; HL -> 4 bytes (lo first) : DEHL = that value.  Keeps A.
ld32:
    ld c,(hl)
    inc hl
    ld b,(hl)
    inc hl
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld h,b
    ld l,c
    ret
; HL -> X, DE -> Y (4 bytes each): flags of X - Y, unsigned (Z equal, C if X < Y)
cmpm:
    inc hl
    inc hl
    inc hl
    inc de
    inc de
    inc de
    ld b,4
cm1:
    ld a,(de)
    ld c,a
    ld a,(hl)
    cp c
    ret nz
    dec hl
    dec de
    djnz cm1
    ret

; u8 cls(u8 c) fastcall
_cls:
    ld a,l
    call nv_cls
    ld l,a
    ld h,0
    ret

; pos_t lstartc(void) / pos_t lstart(pos_t p) fastcall : start of the line holding p  (= tx_rfind(p, LF) + 1; POS_NONE + 1 = 0)
_lstartc:
    call ldcur
_lstart:
    push de
    push hl
    ld hl,10
    push hl
    call _tx_rfind
    pop bc
    pop bc
    pop bc
    jr inc32

; pos_t lendc(void) / pos_t lend(pos_t p) fastcall : index of the LF that ends the line holding p
_lendc:
    call ldcur
_lend:
    push de
    push hl
    call _tx_len
    push de
    push hl
    ld hl,10
    push hl
    call _tx_find
    pop bc
    pop bc
    pop bc
    pop bc
    pop bc
    ret

; u8 tgetc(void) : the character under the cursor
_tgetc:
    call ldcur
    push de
    push hl
    call _tx_get
    pop bc
    pop bc
    ret

; void setwant(void) : want = cur - lstartc()
_setwant:
    call _lstartc
    ex de,hl
    ld hl,(_cur)
    or a
    sbc hl,de
    ld (_want),hl
    ret

; void clampcur(void)
_clampcur:
    call _tx_len
    call stL
    ld hl,_cur
    ld de,mv_L
    call cmpm
    jr c,cc1                    ; cur < len
    ld hl,(mv_L)
    ld de,(mv_L+2)
    call dec32
    call stcur
cc1:
    ld a,(_mode)
    cp 1                        ; M_INSERT: the cursor may sit on the line end
    ret z
    call _lstartc
    call stP
    call _lendc
    call stQ
    ld hl,_cur
    ld de,mv_Q
    call cmpm
    ret c                       ; cur < e
    ld hl,mv_P
    ld de,mv_Q
    call cmpm
    ret nc                      ; empty line
    call ldQ
    call dec32
    jp stcur

; void sethcur(pos_t p) fastcall
_sethcur:
    call stcur
    call _clampcur
    jr _setwant

; void gotoline(pos_t n) fastcall
_gotoline:
    push de
    push hl
    call _tx_nthline
    pop bc
    pop bc
    jr _sethcur

; lmv: DEHL = start of a line, A = down -> DEHL = start of the next / previous line, or POS_NONE
lmv:
    or a
    jr z,lmu
    call _lend
    call inc32
    ld (mv_T),hl
    ld (mv_T+2),de
    call _tx_len
    call stL
    ld hl,mv_T
    ld de,mv_L
    call cmpm
    jr nc,lmnone
    ld hl,(mv_T)
    ld de,(mv_T+2)
    ret
lmu:
    ld a,h
    or l
    or d
    or e
    jr z,lmnone
    call dec32
    jp _lstart
lmnone:
    ld hl,0FFFFh
    ld d,h
    ld e,l
    ret

; pos_t lmove(pos_t p, u8 down)
_lmove:
    ld hl,2
    add hl,sp
    ld a,(hl)
    inc hl
    inc hl
    call ld32
    jr lmv

; pos_t lmoven(pos_t p, u16 n, u8 down) : n lines down / up, or POS_NONE
_lmoven:
    ld hl,2
    add hl,sp
    ld a,(hl)
    ld (mv_dn),a
    inc hl
    inc hl
    ld c,(hl)
    inc hl
    ld b,(hl)
    inc hl
    ld (mv_n),bc
    call ld32
lmn1:
    ld bc,(mv_n)
    ld a,b
    or c
    ret z
    dec bc
    ld (mv_n),bc
    call isnone
    ret z
    ld a,(mv_dn)
    call lmv
    jr lmn1

; (called first thing from a C entry with the arguments (u16 n, u8 down)) -> mv_n, mv_dn
args_nd:
    ld hl,4
    add hl,sp
    ld a,(hl)
    ld (mv_dn),a
    inc hl
    inc hl
    ld c,(hl)
    inc hl
    ld b,(hl)
    ld (mv_n),bc
    ret

; pos_t para(u16 n, u8 down) : { } the blank line n paragraphs away (or the end / start of the text)
_para:
    call args_nd
para_r:                         ; (asm entry: mv_n, mv_dn set)
    call _lstartc
    call stP
pa1:
    ld bc,(mv_n)
    ld a,b
    or c
    jp z,ldP
    dec bc
    ld (mv_n),bc
    xor a
    ld (mv_seen),a
pa2:
    call ldP
    call _lend
    call stQ
    ld hl,mv_P
    ld de,mv_Q
    call cmpm
    jr z,pa3                    ; a blank line
    ld a,1
    ld (mv_seen),a
    jr pa4
pa3:
    ld a,(mv_seen)
    or a
    jr nz,pa1
pa4:
    call ldP
    ld a,(mv_dn)
    call lmv
    call isnone
    jr z,pa5
    call stP
    jr pa2
pa5:
    ld a,(mv_dn)
    or a
    jp z,ldP
    jp ldQ

; void vmove(u16 n, u8 down) : j k keeping the wanted column
_vmove:
    call args_nd
vmove_r:                        ; (asm entry: mv_n, mv_dn set)
    call _lstartc
    call stP
vm1:
    ld bc,(mv_n)
    ld a,b
    or c
    jr z,vm2
    dec bc
    ld (mv_n),bc
    call ldP
    ld a,(mv_dn)
    call lmv
    call isnone
    jr z,vm2
    call stP
    jr vm1
vm2:
    call ldP
    call _lend
    ld bc,(mv_P)
    or a
    sbc hl,bc
    ex de,hl                    ; DE = line length
    ld hl,(_want)               ; HL = column
    ld a,(_mode)
    cp 1
    jr nz,vm3
    or a
    sbc hl,de
    add hl,de
    jr c,vm5                    ; col < len
    ld h,d
    ld l,e
    jr vm5
vm3:
    ld a,d
    or e
    jr nz,vm4
    ld h,a
    ld l,a
    jr vm5
vm4:
    or a
    sbc hl,de
    add hl,de
    jr c,vm5
    ld h,d
    ld l,e
    dec hl
vm5:
    ex de,hl                    ; DE = column
    ld hl,(mv_P)
    add hl,de
    ex de,hl                    ; DE = low word of the result
    ld hl,(mv_P+2)
    jr nc,vm6
    inc hl
vm6:
    ex de,hl
    jp stcur

; A = nv_c = class of the character at nv_p
nw_cls:
    ld hl,(nv_p)
    ld de,(nv_p+2)
    push de
    push hl
    call _tx_get
    pop af
    pop af
    ld a,l
    call nv_cls
    ld (nv_c),a
    ret
; nv_end = text length (also left in DEHL)
endlen:
    call _tx_len
    ld (nv_end),hl
    ld (nv_end+2),de
    ret
; C if DEHL < nv_end.  Keeps DEHL.
ltend:
    push hl
    ld bc,(nv_end)
    or a
    sbc hl,bc
    ld h,d
    ld l,e
    ld bc,(nv_end+2)
    sbc hl,bc
    pop hl
    ret
ldp1:                           ; DEHL = nv_p + 1
    ld hl,(nv_p)
    ld de,(nv_p+2)
    jp inc32

; pos_t nextword(pos_t p) fastcall
_nextword:
    call stp
    call endlen
    call nw_cls
    or a
    call nz,sf_l                ; the rest of this word ...
    xor a
    ld (nv_c),a
    jp sf_l                     ; ... then the blanks after it

; (called first thing from a C entry with the arguments (pos_t p, u16 n)) -> nv_p, mv_n
args_pn:
    ld hl,4
    add hl,sp
    ld c,(hl)
    inc hl
    ld b,(hl)
    inc hl
    ld (mv_n),bc
    ld de,nv_p
    ld bc,4
    ldir
    ret

; pos_t endword(pos_t p, u16 n) : the last character of the n-th word end from p
_endword:
    call args_pn
ew1:
    ld bc,(mv_n)
    ld a,b
    or c
    jp z,sf_d
    dec bc
    ld (mv_n),bc
    call endlen
    call ldp1
    call ltend
    call c,stp                  ; if (p + 1 < len) p++
    ld hl,(nv_end)
    ld de,(nv_end+2)
    call dec32
    ld (nv_end),hl
    ld (nv_end+2),de
    xor a
    ld (nv_c),a
    call sf_l                   ; p = skipf(p, len - 1, 0)
    call nw_cls
    call ldp1
    call stp
    call endlen
    call sf_l                   ; p = skipf(p + 1, len, c) - 1
    call dec32
    call stp
    jr ew1

; pos_t backword(pos_t p, u16 n)
_backword:
    call args_pn
bw1:
    ld bc,(mv_n)
    ld a,b
    or c
    jp z,sf_d
    dec bc
    ld (mv_n),bc
    ld hl,(nv_p)
    ld de,(nv_p+2)
    ld a,h
    or l
    or d
    or e
    jp z,sf_d
    call dec32
    call stp
    xor a
    ld (nv_c),a
    ld (nv_o),a
    call sb_l                   ; p = skipb(p - 1, 0, 0)
    call nw_cls
    ld a,1
    ld (nv_o),a
    call sb_l                   ; p = skipb(p, c, 1)
    jr bw1

; void wordfwd(u16 n) fastcall
_wordfwd:
    ld (mv_n),hl
    call ldcur
wf1:
    push hl
    ld hl,(mv_n)
    ld a,h
    or l
    dec hl
    ld (mv_n),hl
    pop hl
    jr z,wf2
    call _nextword              ; leaves nv_end = text length
    call ltend
    jr c,wf1
    ld hl,(nv_end)
    ld de,(nv_end+2)
    call dec32
wf2:
    jp _sethcur

; void wordback(u16 n) fastcall
_wordback:
    ld (mv_n),hl
    call ldcur
    call stp
    call bw1
    jp _sethcur

    SECTION bss_user
nv_p:   defs 4
mv_P:   defs 4
mv_Q:   defs 4
mv_T:   defs 4
mv_L:   defs 4
mv_n:   defs 2
mv_dn:  defb 0
mv_seen: defb 0
nv_end: defs 4
nv_c:   defb 0
nv_o:   defb 0
nv_len: defs 4
nv_m:   defb 0
nv_d:   defb 0
to_s:   defs 4
to_k:   defb 0
to_a:   defb 0
to_cc:  defb 0
to_cl:  defb 0
to_ls:  defs 4
to_le:  defs 4
to_len: defs 4
to_cur: defs 4

    SECTION code_user
; void casebuf(u8 *p, u8 n, u8 op)  -- op '~' toggles the case of letters, 'U' upcases, 'u' downcases
_casebuf:
    ld hl,2
    add hl,sp
    ld a,(hl)                  ; op
    inc hl
    inc hl
    ld b,(hl)                  ; n
    inc hl
    inc hl
    ld e,(hl)
    inc hl
    ld d,(hl)
    ex de,hl                   ; hl = p
    ld c,a
    inc b
    jr cb_e
cb_l:
    ld a,(hl)
    or 20h
    sub 'a'
    cp 26
    jr nc,cb_n                 ; not a letter
    ld a,c
    cp '~'
    jr z,cb_f
    ld a,(hl)
    and 20h                    ; 20h when the letter is lower case
    ld d,a
    ld a,c
    cp 'U'
    ld a,20h
    jr z,cb_u
    xor a
cb_u:
    cp d
    jr nz,cb_n
cb_f:
    ld a,(hl)
    xor 20h
    ld (hl),a
cb_n:
    inc hl
cb_e:
    djnz cb_l
    ret

; ---- text objects: i/a + quote or bracket.  nv_o = back flag, nv_m = other, nv_c = want, nv_end = limit, nv_p = start
p_get:                         ; A = byte at nv_p
    ld hl,(nv_p+2)
    push hl
    ld hl,(nv_p)
    push hl
    call _tx_get
    pop af
    pop af
    ld a,l
    ret
p_inc:
    ld hl,(nv_p)
    inc hl
    ld (nv_p),hl
    ld a,h
    or l
    ret nz
    ld hl,(nv_p+2)
    inc hl
    ld (nv_p+2),hl
    ret
p_dec:                         ; carry set when p was 0 (not changed)
    ld hl,(nv_p)
    ld a,h
    or l
    jr nz,pd_1
    ld hl,(nv_p+2)
    ld a,h
    or l
    scf
    ret z
    dec hl
    ld (nv_p+2),hl
    ld hl,0
pd_1:
    dec hl
    ld (nv_p),hl
    or a
    ret
bs_core:                       ; scan from nv_p; carry set = not found, else nv_p = the position of `want` at depth 0
    xor a
    ld (nv_d),a
bc_l:
    ld a,(nv_o)
    or a
    jr nz,bc_g
    ld hl,(nv_p)
    ld de,(nv_end)
    or a
    sbc hl,de
    ld hl,(nv_p+2)
    ld de,(nv_end+2)
    sbc hl,de
    jr c,bc_g
    scf
    ret
bc_g:
    call p_get
    ld hl,nv_c
    cp (hl)
    jr nz,bc_o
    ld a,(nv_d)
    or a
    ret z                      ; found (carry clear)
    dec a
    ld (nv_d),a
    jr bc_n
bc_o:
    ld hl,nv_m
    cp (hl)
    jr nz,bc_n
    ld hl,nv_d
    inc (hl)
bc_n:
    ld a,(nv_o)
    or a
    jr z,bc_f
    call p_dec
    ret c
    jr bc_l
bc_f:
    call p_inc
    jr bc_l
; A=kind(i/a), result: HL = 1 done (gs/ge set), 0 nothing to do, 2 = not an object here
; int tobj(pos_t cur, pos_t ls, pos_t le, pos_t len, u8 kind, u8 k)   frame: k +2, kind +4, len +6, le +10, ls +14, cur +18
_tobj:
    ld hl,2
    add hl,sp
    ld a,(hl)
    ld (to_k),a
    inc hl
    inc hl
    ld a,(hl)
    ld (to_a),a
    inc hl
    inc hl
    ld de,to_len
    ld bc,4
    ldir
    ld de,to_le
    ld bc,4
    ldir
    ld de,to_ls
    ld bc,4
    ldir
    ld de,to_cur
    ld bc,4
    ldir
    ld a,(to_k)
    cp '"'
    jr z,to_q
    cp 39
    jr z,to_q
    cp '`'
    jr z,to_q
    ld hl,to_tab               ; bracket table: key, open, close
to_t:
    ld a,(hl)
    or a
    jp z,to_no2
    ld b,a
    inc hl
    ld a,(hl)
    inc hl
    ld c,(hl)
    inc hl
    ld d,a
    ld a,(to_k)
    cp b
    jr nz,to_t
    ld a,d
    ld (to_cc),a
    ld a,c
    ld (to_cl),a
    ld hl,(to_cur)
    ld (nv_p),hl
    ld hl,(to_cur+2)
    ld (nv_p+2),hl
    call p_get
    ld hl,to_cl
    cp (hl)
    jr nz,to_b1
    call p_dec                 ; cursor on the closing bracket: start before it
to_b1:
    ld a,1
    ld (nv_o),a
    ld a,(to_cc)
    ld (nv_c),a
    ld a,(to_cl)
    ld (nv_m),a
    call bs_core
    jp c,to_no
    call to_save_s
    call p_inc
    xor a
    ld (nv_o),a
    ld a,(to_cl)
    ld (nv_c),a
    ld a,(to_cc)
    ld (nv_m),a
    ld hl,(to_len)
    ld (nv_end),hl
    ld hl,(to_len+2)
    ld (nv_end+2),hl
    call bs_core
    jp c,to_no
    jr to_fin
to_q:                          ; quotes: the nearest before the cursor on this line, else the next one; then the one after it
    ld (nv_c),a
    xor a
    ld (nv_m),a
    ld hl,(to_cur)
    ld (nv_p),hl
    ld hl,(to_cur+2)
    ld (nv_p+2),hl
    ld a,1
    ld (nv_o),a
    call bs_core
    jr c,to_q2
    ld hl,(nv_p)               ; found: must be on this line (p >= ls)
    ld de,(to_ls)
    or a
    sbc hl,de
    ld hl,(nv_p+2)
    ld de,(to_ls+2)
    sbc hl,de
    jr nc,to_q3
to_q2:
    ld hl,(to_cur)
    ld (nv_p),hl
    ld hl,(to_cur+2)
    ld (nv_p+2),hl
    xor a
    ld (nv_o),a
    ld hl,(to_le)
    ld (nv_end),hl
    ld hl,(to_le+2)
    ld (nv_end+2),hl
    call bs_core
    jp c,to_no
to_q3:
    call to_save_s
    call p_inc
    xor a
    ld (nv_o),a
    ld hl,(to_le)
    ld (nv_end),hl
    ld hl,(to_le+2)
    ld (nv_end+2),hl
    call bs_core
    jp c,to_no
to_fin:                        ; to_s .. nv_p are the two delimiters
    ld a,(to_a)
    cp 'i'
    jr nz,to_aa
    ld hl,(nv_p)               ; e = closing delimiter
    ld (_ge),hl
    ld hl,(nv_p+2)
    ld (_ge+2),hl
    ld hl,(to_s)               ; s = opening + 1
    ld (nv_p),hl
    ld hl,(to_s+2)
    ld (nv_p+2),hl
    call p_inc
    call p_get
    cp 10
    call z,p_inc               ; skip the newline right after the opening bracket
    jr to_st
to_aa:
    call p_inc                 ; e = closing + 1
    ld hl,(nv_p)
    ld (_ge),hl
    ld hl,(nv_p+2)
    ld (_ge+2),hl
    ld hl,(to_s)
    ld (nv_p),hl
    ld hl,(to_s+2)
    ld (nv_p+2),hl
to_st:
    ld hl,(nv_p)
    ld (_gs),hl
    ld hl,(nv_p+2)
    ld (_gs+2),hl
    ld hl,1
    ret
to_no:
    ld hl,0
    ret
to_no2:
    ld hl,2
    ret
to_save_s:
    ld hl,(nv_p)
    ld (to_s),hl
    ld hl,(nv_p+2)
    ld (to_s+2),hl
    ret
to_tab:
    defb '(',  '(', ')'
    defb ')',  '(', ')'
    defb 'b',  '(', ')'
    defb '[',  '[', ']'
    defb ']',  '[', ']'
    defb '{',  '{', '}'
    defb '}',  '{', '}'
    defb 'B',  '{', '}'
    defb '<',  '<', '>'
    defb '>',  '<', '>'
    defb 0
