; edit_z80.asm - small edit and view commands (asm twins of functions in core/ed_op.c and core/ed_normal.c; -DM_ASM)
;   findch (f F t T), cmd_x (x), case_toggle (~), cmd_join (J gJ), shift (> <), screen_line (H M L), scroll_view (Ctrl-E Ctrl-Y)
    SECTION code_user
    PUBLIC tinsat
    PUBLIC _findch, _cmd_x, _case_toggle, _cmd_join, _shift, _screen_line, _scroll_view
    EXTERN ldcur, stcur, stP, ldP, stQ, ldQ, stL, inc32, dec32, isnone, cmpm, subm, addm, pusha, mv_P, mv_Q, mv_L, mv_n, mv_dn
    EXTERN lmv, lmn1, opa, tgetat, tdel1
    EXTERN _lstartc, _lendc, _lstart, _lend, _firstnb, _sethcur, _clampcur, _setwant
    EXTERN _tx_len, _tx_count, _tins, _tdel, _casechg
    EXTERN _cur, _gs, _ge, _glin, _top, _shvalid

; tins(DEHL, A)
tinsat:
    ld c,a
    push de
    push hl
    ld a,c
    call pusha
    call _tins
    pop bc
    pop bc
    pop bc
    ret

; u16 findch(u8 k, u8 ch, u16 n) : distance from the cursor to the n-th ch on this line (k = f F t T), or 0FFFFh
_findch:
    ld hl,2
    add hl,sp
    ld e,(hl)
    inc hl
    ld d,(hl)
    inc hl
    ld (ed_n),de
    ld a,(hl)
    ld (fc_ch),a
    inc hl
    inc hl
    ld a,(hl)
    ld (fc_k),a
    call _lstartc
    call stP
    ex de,hl                    ; DE = low word of the line start
    ld hl,(_cur)
    or a
    sbc hl,de
    ld (fc_i0),hl
    ld (fc_i),hl
    call _lendc
    ld de,(mv_P)
    or a
    sbc hl,de
    ld (fc_len),hl
fc1:
    ld hl,(ed_n)
    ld a,h
    or l
    jr z,fc4
    dec hl
    ld (ed_n),hl
fc2:
    ld hl,(fc_i)
    ld a,(fc_k)
    cp 'Z'+1
    jr c,fc3
    inc hl                      ; forward
    ld (fc_i),hl
    ld de,(fc_len)
    or a
    sbc hl,de
    jr nc,fc_fail
    jr fc3a
fc3:
    ld a,h                      ; backward
    or l
    jr z,fc_fail
    dec hl
    ld (fc_i),hl
fc3a:
    ld hl,(fc_i)
    ld de,mv_P
    call addm
    call tgetat
    ld hl,fc_ch
    cp (hl)
    jr nz,fc2
    jr fc1
fc4:
    ld hl,(fc_i)
    ld a,(fc_k)
    cp 't'
    jr nz,fc5
    dec hl
    jr fc6
fc5:
    cp 'T'
    jr nz,fc6
    inc hl
fc6:
    ld de,(fc_i0)
    ld a,(fc_k)
    cp 'Z'+1
    jr c,fc7
    or a
    sbc hl,de
    ret
fc7:
    ex de,hl
    or a
    sbc hl,de
    ret
fc_fail:
    ld hl,0FFFFh
    ret

; void cmd_x(u16 n) fastcall : x
_cmd_x:
    ld (ed_n),hl
    call _lendc
    call stP
    ld hl,_cur
    ld de,mv_P
    call cmpm
    ret nc                      ; on an empty line
    ld hl,mv_P
    ld de,_cur
    call subm
    ld a,d
    or e
    jr nz,cx1
    ld bc,(ed_n)
    sbc hl,bc
    add hl,bc
    jr nc,cx1
    ld (ed_n),hl                ; no more than the rest of the line
cx1:
    call ldcur
    ld (_gs),hl
    ld (_gs+2),de
    ld hl,(ed_n)
    ld de,_cur
    call addm
    ld (_ge),hl
    ld (_ge+2),de
    xor a
    ld (_glin),a
    ld a,'d'
    jp opa

; void case_toggle(u16 n) fastcall : ~
_case_toggle:
    ld (ed_n),hl
    call _lendc
    ld de,(_cur)
    or a
    sbc hl,de
    ld bc,(ed_n)
    or a
    sbc hl,bc
    add hl,bc
    jr nc,ct1
    ld (ed_n),hl
ct1:
    ld hl,(ed_n)
    ld a,h
    or l
    ret z
    ld de,_cur
    call addm
    ld bc,(_cur+2)
    push bc
    ld bc,(_cur)
    push bc
    push de
    push hl
    ld a,'~'
    call pusha
    call _casechg
    pop bc
    pop bc
    pop bc
    pop bc
    pop bc
    ld hl,(ed_n)
    ld de,_cur
    call addm
    call stcur
    call _clampcur
    jp _setwant

; void cmd_join(u16 n, u8 sp) : J (sp = 1: one blank between the lines) and gJ (sp = 0)
_cmd_join:
    ld hl,2
    add hl,sp
    ld a,(hl)
    ld (cj_sp),a
    inc hl
    inc hl
    ld a,(hl)
    inc hl
    ld h,(hl)
    ld l,a
    ld a,h                      ; the count is the number of lines: 2 or less = one join
    or a
    jr nz,cj0
    ld a,l
    cp 2
    jr nc,cj0
    ld l,2
cj0:
    dec hl
    ld (ed_n),hl
cj1:
    call _lendc
    call stP
    call inc32
    call stQ
    call _tx_len
    call stL
    ld hl,mv_Q
    ld de,mv_L
    call cmpm
    ret nc                      ; the last line
    call ldP
    call tdel1
    ld a,(cj_sp)
    or a
    jr z,cj5
cj2:
    call _tx_len                ; drop the indent of the joined line
    call stL
    ld hl,mv_P
    ld de,mv_L
    call cmpm
    jr nc,cj3
    call ldP
    call tgetat
    cp ' '
    jr z,cj2a
    cp 9
    jr nz,cj3
cj2a:
    call ldP
    call tdel1
    jr cj2
cj3:
    call ldP
    ld a,h
    or l
    or d
    or e
    jr z,cj5
    call dec32
    call tgetat
    cp 10
    jr z,cj5
    call ldP
    call tgetat
    cp 10
    jr z,cj5
    call ldP
    ld a,' '
    call tinsat
cj5:
    call ldP
    call _sethcur
    ld hl,(ed_n)
    dec hl
    ld (ed_n),hl
    ld a,h
    or l
    jp nz,cj1
    ret

; void shift(u8 op) fastcall : > < on every line of [gs, ge): one tab in, or one tab / up to 8 blanks out
_shift:
    ld a,l
    ld (sh_op),a
    ld hl,(_gs+2)
    push hl
    ld hl,(_gs)
    push hl
    ld hl,(_ge+2)
    push hl
    ld hl,(_ge)
    push hl
    ld hl,10
    push hl
    call _tx_count
    pop bc
    pop bc
    pop bc
    pop bc
    pop bc
    ld (ed_n),hl
    ld hl,(_gs)
    ld de,(_gs+2)
    call _lstart
    ld (_gs),hl
    ld (_gs+2),de
    call stP
sh1:
    ld hl,(ed_n)
    ld a,h
    or l
    jr z,sh9
    dec hl
    ld (ed_n),hl
    call ldP
    call tgetat
    ld c,a
    ld a,(sh_op)
    cp '>'
    jr nz,sh3
    ld a,c
    cp 10
    jr z,sh8                    ; an empty line stays empty
    call ldP
    ld a,9
    call tinsat
    jr sh8
sh3:
    ld a,c
    cp 9
    ld b,1
    jr z,sh6
    xor a
    ld (sh_n),a
sh4:
    ld a,(sh_n)
    cp 8
    jr nc,sh5
    ld l,a
    ld h,0
    ld de,mv_P
    call addm
    call tgetat
    cp ' '
    jr nz,sh5
    ld hl,sh_n
    inc (hl)
    jr sh4
sh5:
    ld a,(sh_n)
    or a
    jr z,sh8
    ld b,a
sh6:
    call ldP
    push de
    push hl
    ld hl,0
    push hl
    ld l,b
    push hl
    call _tdel
    pop bc
    pop bc
    pop bc
    pop bc
sh8:
    call ldP
    call _lend
    call inc32
    call stP
    jr sh1
sh9:
    ld hl,(_gs)
    ld de,(_gs+2)
    call _firstnb
    jp _sethcur

; void screen_line(u8 k) fastcall : H M L
_screen_line:
    ld a,l
    ld (fc_k),a
    ld hl,(_top)
    ld de,(_top+2)
    call stQ
    xor a
    ld (sh_n),a
sl1:
    ld a,(sh_n)                 ; how many lines are on the screen below the top one
    cp 23
    jr nc,sl2
    call ldQ
    ld a,1
    call lmv
    call isnone
    jr z,sl2
    call stQ
    ld hl,sh_n
    inc (hl)
    jr sl1
sl2:
    ld a,(sh_n)
    ld l,a
    ld h,0
    ld a,(fc_k)
    cp 'H'
    jr nz,sl3
    ld l,h
    jr sl4
sl3:
    cp 'M'
    jr nz,sl4
    srl l
sl4:
    ld (mv_n),hl
    ld a,1
    ld (mv_dn),a
    ld hl,(_top)
    ld de,(_top+2)
    call lmn1
    call _firstnb
    jp _sethcur

; void scroll_view(u16 n, u8 down) : Ctrl-E / Ctrl-Y, keeping the cursor on the screen
_scroll_view:
    ld hl,2
    add hl,sp
    ld a,(hl)
    ld (sh_op),a
    inc hl
    inc hl
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld (ed_n),de
sv1:
    ld hl,(ed_n)
    ld a,h
    or l
    jr z,sv2
    dec hl
    ld (ed_n),hl
    ld hl,(_top)
    ld de,(_top+2)
    ld a,(sh_op)
    call lmv
    call isnone
    jr z,sv2
    ld (_top),hl
    ld (_top+2),de
    jr sv1
sv2:
    xor a
    ld (_shvalid),a             ; the view moved behind the renderer's back: redraw everything
    call _lstartc
    call stP
    ld hl,mv_P
    ld de,_top
    call cmpm
    jr nc,sv3
    ld hl,(_top)
    ld de,(_top+2)
    jp _sethcur
sv3:
    ld hl,(_top)
    ld de,(_top+2)
    call stQ
    ld a,23
    ld (sh_n),a
sv4:
    call ldQ
    ld a,1
    call lmv
    call isnone
    jr z,sv5
    call stQ
    ld hl,sh_n
    dec (hl)
    jr nz,sv4
sv5:
    call _lstartc
    call stP
    ld hl,mv_Q
    ld de,mv_P
    call cmpm
    ret nc
    call ldQ
    jp _sethcur

; ======================================================================================================================
; p P, yank, ~ u U on a range, text objects, * #
    PUBLIC _cmd_paste, _yankrange, _casechg, _textobj, _star
    EXTERN stp, sf_l, sb_l, nv_c, nv_o, nv_end, _tgetc, _cls, _tobj, _dosearch, _setmsg, _casebuf, _tinsn
    EXTERN _tx_free, _tx_read, _tx_aux_get, _tx_aux_put, _tx_aux_move, _mins, _touched, _ulog_add
    EXTERN _reg, _rlen, _roff, _rflg, _ylen, _ylin, _ynl, _ibuf, _rowc, _ugrp, _m_full, _srch, _slen, _sback
    defc ISZ = 64
    defc YSZ = 1024
    defc RBASE = 2048
    defc SRCHSZ = 24

; pi_m = min(HL, ISZ)
chunk:
    ld a,h
    or a
    jr nz,ch1
    ld a,l
    cp ISZ+1
    jr c,ch2
ch1:
    ld hl,ISZ
ch2:
    ld (pi_m),hl
    ret

; register reg -> the unnamed register (for p P).  Z if it is empty.
regload:
    ld a,(_reg)
    or 20h
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
    jr nz,rl1
    ld hl,s_rempty
    push hl
    call _setmsg
    pop bc
    xor a
    ret
rl1:
    ld (_ylen),hl
    push de
    ld bc,0
    push bc
    ld hl,_roff
    add hl,de
    ld a,(hl)
    inc hl
    ld h,(hl)
    ld l,a
    ld bc,RBASE
    add hl,bc
    push hl
    ld hl,(_ylen)
    push hl
    call _tx_aux_move
    pop bc
    pop bc
    pop bc
    pop de
    srl e
    ld hl,_rflg
    add hl,de
    ld a,(hl)
    ld b,a
    and 1
    ld (_ylin),a
    ld a,b
    rrca
    and 1
    ld (_ynl),a
    or 1
    ret

; void cmd_paste(u8 before, u16 n) : p (before = 0) and P
_cmd_paste:
    ld hl,2
    add hl,sp
    ld e,(hl)
    inc hl
    ld d,(hl)
    inc hl
    ld (ed_n),de
    ld a,(hl)
    ld (cj_sp),a
    ld a,(_reg)
    or a
    jr z,cp1
    call regload
    ret z
cp1:
    ld hl,(_ylen)
    ld a,h
    or l
    ret z
    ld a,(_ylin)
    or a
    jr z,cp3
    ld a,(cj_sp)                ; whole lines go above / below this line
    or a
    jr z,cp2
    call _lstartc
    jr cp5
cp2:
    call _lendc
    call inc32
    jr cp5
cp3:
    ld a,(cj_sp)
    or a
    jr nz,cp4
    call _tgetc
    ld a,l
    cp 10
    jr z,cp4
    call ldcur
    call inc32
    jr cp5
cp4:
    call ldcur
cp5:
    ld (cp_pos),hl
    ld (cp_pos+2),de
    ld (cp_at),hl
    ld (cp_at+2),de
    call _tx_free               ; room for count copies?
    call stQ
    ld bc,(ed_n)
cp6:
    ld hl,(mv_Q)
    ld de,(_ylen)
    or a
    sbc hl,de
    ld (mv_Q),hl
    jr nc,cp7
    ld hl,(mv_Q+2)
    ld a,h
    or l
    jr z,cp_full
    dec hl
    ld (mv_Q+2),hl
cp7:
    dec bc
    ld a,b
    or c
    jr nz,cp6
    ld hl,(ed_n)
    ld (cp_j),hl
cp9:
    call pins
    ld hl,(_ylen)
    ld de,cp_at
    call addm
    ld (cp_at),hl
    ld (cp_at+2),de
    ld hl,(cp_j)
    dec hl
    ld (cp_j),hl
    ld a,h
    or l
    jr nz,cp9
    ld hl,(cp_pos)
    ld de,(cp_pos+2)
    ld a,(_ylin)
    ld b,a
    ld a,(_ynl)
    or b
    jr nz,cp10
    ld hl,(cp_at)               ; characters within a line: the cursor goes to the last one pasted
    ld de,(cp_at+2)
    call dec32
cp10:
    call stcur
    call _clampcur
    jp _setwant
cp_full:
    ld hl,_m_full
    push hl
    call _setmsg
    pop bc
    ret

; insert the unnamed register at cp_at (one undo entry)
pins:
    ld hl,0
    ld (pi_o),hl
pn1:
    ld hl,(_ylen)
    ld de,(pi_o)
    or a
    sbc hl,de
    jr z,pn3
    call chunk
    ld hl,_ibuf
    push hl
    ld hl,(pi_o)
    push hl
    ld hl,(pi_m)
    push hl
    call _tx_aux_get
    pop bc
    pop bc
    pop bc
    ld hl,(pi_o)
    ld de,cp_at
    call addm
    push de
    push hl
    ld hl,_ibuf
    push hl
    ld hl,0
    push hl
    ld hl,(pi_m)
    push hl
    call _mins
    pop bc
    pop bc
    pop bc
    pop bc
    pop bc
    ld hl,(pi_o)
    ld de,(pi_m)
    add hl,de
    ld (pi_o),hl
    jr pn1
pn3:
    ld hl,(cp_at+2)
    push hl
    ld hl,(cp_at)
    push hl
    call _touched
    pop bc
    pop bc
    ld hl,0                     ; ulog_add(0, T_INS, pos, ylen, 0, 0, ugrp)
    push hl
    push hl
    ld hl,(cp_at+2)
    push hl
    ld hl,(cp_at)
    push hl
    ld hl,0
    push hl
    ld hl,(_ylen)
    push hl
    ld hl,0
    push hl
    push hl
    ld a,(_ugrp)
    call pusha
    call _ulog_add
    ld hl,18
    add hl,sp
    ld sp,hl
    ret

; void yankrange(void) : [gs, ge) -> the unnamed register (ylen, ynl = it holds a line break)
_yankrange:
    ld hl,_ge
    ld de,_gs
    call subm
    ld a,d
    or e
    jr nz,yk_big
    push hl
    ld de,YSZ+1
    or a
    sbc hl,de
    pop hl
    jr c,yk1
yk_big:
    ld hl,0
    ld (_ylen),hl
    ld hl,s_ybig
    push hl
    call _setmsg
    pop bc
    ret
yk1:
    ld (yk_n),hl
    xor a
    ld (_ynl),a
    ld hl,0
    ld (pi_o),hl
yk2:
    ld hl,(yk_n)
    ld de,(pi_o)
    or a
    sbc hl,de
    jr z,yk5
    call chunk
    ld hl,(pi_o)
    ld de,_gs
    call addm
    ld bc,_ibuf
    push bc
    push de
    push hl
    ld hl,0
    push hl
    ld hl,(pi_m)
    push hl
    call _tx_read
    pop bc
    pop bc
    pop bc
    pop bc
    pop bc
    ld hl,(pi_o)
    push hl
    ld hl,_ibuf
    push hl
    ld hl,(pi_m)
    push hl
    call _tx_aux_put
    pop bc
    pop bc
    pop bc
    ld hl,_ibuf
    ld bc,(pi_m)
    ld a,10
    cpir
    jr nz,yk4
    ld a,1
    ld (_ynl),a
yk4:
    ld hl,(pi_o)
    ld de,(pi_m)
    add hl,de
    ld (pi_o),hl
    jr yk2
yk5:
    ld hl,(yk_n)
    ld (_ylen),hl
    ret

; void casechg(pos_t s, pos_t e, u8 op) : ~ u U over [s, e), 64 bytes at a time (each chunk = one delete + one insert in the undo log)
_casechg:
    ld hl,2
    add hl,sp
    ld a,(hl)
    ld (sh_op),a
    inc hl
    inc hl
    ld de,cc_e
    ld bc,8
    ldir
cc1:
    ld hl,cc_e
    ld de,cc_s
    call subm
    ret c
    ld a,h
    or l
    or d
    or e
    ret z
    ld a,d
    or e
    jr z,cc2
    ld hl,ISZ
cc2:
    call chunk
    ld hl,_rowc                 ; tx_read(rowc, s, m)
    push hl
    ld hl,(cc_s+2)
    push hl
    ld hl,(cc_s)
    push hl
    ld hl,0
    push hl
    ld hl,(pi_m)
    push hl
    call _tx_read
    pop bc
    pop bc
    pop bc
    pop bc
    pop bc
    ld hl,_rowc                 ; casebuf(rowc, m, op)
    push hl
    ld hl,(pi_m)
    push hl
    ld a,(sh_op)
    call pusha
    call _casebuf
    pop bc
    pop bc
    pop bc
    ld hl,(cc_s+2)              ; tdel(s, m)
    push hl
    ld hl,(cc_s)
    push hl
    ld hl,0
    push hl
    ld hl,(pi_m)
    push hl
    call _tdel
    pop bc
    pop bc
    pop bc
    pop bc
    ld hl,(cc_s+2)              ; tinsn(s, rowc, m)
    push hl
    ld hl,(cc_s)
    push hl
    ld hl,_rowc
    push hl
    ld hl,0
    push hl
    ld hl,(pi_m)
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
    ld hl,(pi_m)
    ld de,cc_s
    call addm
    ld (cc_s),hl
    ld (cc_s+2),de
    jp cc1

; void textobj(u8 op, u8 kind, u8 k) : operator / visual selection on a text object (kind = i or a; k = w " ' ` ( [ { < ...)
_textobj:
    ld hl,2
    add hl,sp
    ld a,(hl)
    ld (fc_k),a
    inc hl
    inc hl
    ld a,(hl)
    ld (fc_ch),a
    inc hl
    inc hl
    ld a,(hl)
    ld (sh_op),a
    call _lstartc
    ld (cc_s),hl
    ld (cc_s+2),de
    call _lendc
    ld (cc_e),hl
    ld (cc_e+2),de
    ld hl,(_cur+2)              ; tobj(cur, ls, le, tlen, kind, k): quotes and brackets (nav_z80.asm)
    push hl
    ld hl,(_cur)
    push hl
    ld hl,(cc_s+2)
    push hl
    ld hl,(cc_s)
    push hl
    push de
    ld hl,(cc_e)
    push hl
    call _tx_len
    push de
    push hl
    ld a,(fc_ch)
    call pusha
    ld a,(fc_k)
    call pusha
    call _tobj
    ld a,l
    ld hl,20
    add hl,sp
    ld sp,hl
    cp 1
    jp z,to_apply
    or a
    ret z
    ld a,(fc_k)
    cp 'w'
    ret nz
    call _tgetc                 ; iw aw
    call _cls
    ld a,l
    ld (nv_c),a
    ld (sh_n),a
    call ldcur
    call stp
    ld a,1
    ld (nv_o),a
    call sb_l
    call max_ls
    call ldcur
    call stp
    ld hl,(cc_e)
    ld (nv_end),hl
    ld hl,(cc_e+2)
    ld (nv_end+2),hl
    call sf_l
    ld (_ge),hl
    ld (_ge+2),de
    ld a,(fc_ch)
    cp 'a'
    jr nz,to_apply
    ld a,(sh_n)
    or a
    jr z,to_apply
    xor a                       ; aw: the blanks after the word, or else the ones before it
    ld (nv_c),a
    call sf_l
    call stQ
    ld hl,mv_Q
    ld de,_ge
    call cmpm
    jr z,to1
    call ldQ
    ld (_ge),hl
    ld (_ge+2),de
    jr to_apply
to1:
    ld hl,(_gs)
    ld de,(_gs+2)
    call stp
    xor a
    ld (nv_c),a
    inc a
    ld (nv_o),a
    call sb_l
    call max_ls
to_apply:
    xor a
    ld (_glin),a
    ld a,(sh_op)
    jp opa
; gs = max(DEHL, start of the line)
max_ls:
    call stQ
    ld hl,mv_Q
    ld de,cc_s
    call cmpm
    jr nc,mx1
    ld hl,(cc_s)
    ld de,(cc_s+2)
    jr mx2
mx1:
    call ldQ
mx2:
    ld (_gs),hl
    ld (_gs+2),de
    ret

; void star(u8 fwd) fastcall : * # - search for the word under (or after) the cursor
_star:
    ld a,l
    ld (cj_sp),a
    call _lstartc
    call stP
    ld de,(mv_P)
    ld hl,(_cur)
    or a
    sbc hl,de
    ld (fc_i),hl
    call _lendc
    ld de,(mv_P)
    or a
    sbc hl,de
    ld (fc_len),hl
st1:
    ld hl,(fc_i)
    ld de,(fc_len)
    or a
    sbc hl,de
    jr nc,st_no
    ld hl,(fc_i)
    call st_cls
    dec a
    jr z,st2
    ld hl,(fc_i)
    inc hl
    ld (fc_i),hl
    jr st1
st_no:
    ld hl,s_noword
    push hl
    call _setmsg
    pop bc
    ret
st2:
    ld hl,(fc_i)                ; back to the start of the word
    ld a,h
    or l
    jr z,st3
    dec hl
    call st_cls
    dec a
    jr nz,st3
    ld hl,(fc_i)
    dec hl
    ld (fc_i),hl
    jr st2
st3:
    xor a
    ld (sh_n),a
st4:
    ld a,(sh_n)
    cp SRCHSZ
    jr nc,st5
    ld l,a
    ld h,0
    ld de,(fc_i)
    add hl,de
    ld (fc_i0),hl
    ld de,(fc_len)
    or a
    sbc hl,de
    jr nc,st5
    ld hl,(fc_i0)
    call st_cls
    dec a
    jr nz,st5
    ld a,(sh_n)
    ld e,a
    ld d,0
    ld hl,_srch
    add hl,de
    ld a,(fc_ch)
    ld (hl),a
    ld hl,sh_n
    inc (hl)
    jr st4
st5:
    ld a,(sh_n)
    ld (_slen),a
    ld e,a
    ld d,0
    ld hl,_srch
    add hl,de
    ld (hl),0
    ld hl,(fc_i)
    ld de,mv_P
    call addm
    call stcur
    ld a,(cj_sp)
    sub 1
    sbc a,a
    and 1
    ld (_sback),a
    ld a,(cj_sp)
    ld l,a
    ld h,0
    jp _dosearch
; A = class of the character at column HL of the line at mv_P (the character itself is left in fc_ch)
st_cls:
    ld de,mv_P
    call addm
    call tgetat
    ld (fc_ch),a
    ld l,a
    call _cls
    ld a,l
    ret

s_rempty: defm "register empty"
    defb 0
s_ybig: defm "yank too big"
    defb 0
s_noword: defm "no word"
    defb 0

    SECTION bss_user
ed_n:   defs 2
pi_o:   defs 2
pi_m:   defs 2
yk_n:   defs 2
cp_j:   defs 2
cp_pos: defs 4
cp_at:  defs 4
cc_e:   defs 4                  ; (cc_e then cc_s: filled by one ldir from the stack)
cc_s:   defs 4
fc_i:   defs 2
fc_i0:  defs 2
fc_len: defs 2
fc_k:   defb 0
fc_ch:  defb 0
cj_sp:  defb 0
sh_op:  defb 0
sh_n:   defb 0
