; ex_z80.asm - the command line: ex commands and / ? search (the asm twin of core/ed_ex.c and dosearch; -DM_ASM)
;   cmd_key  : one key in command-line mode;  runcmd : run the line in cmdbuf (cmdch = ':' '/' '?')
;   dosearch : / ? n N  (line by line with rx_scan from regex_z80.asm)
    SECTION code_user
    PUBLIC _cmd_key, _dosearch
    EXTERN ldcur, stcur, inc32, dec32, cmpm, addm, pusha, opa
    EXTERN _lstartc, _lendc, _lstart, _lend, _sethcur, _gotoline, _clampcur, _setwant, _setmsg
    EXTERN _tx_len, _tx_nthline, _tx_read, _tdel, _tinsn, _rx_scan, _mhere, _lineno, _dosave, _ed_load
    EXTERN _fs_exec, _fs_bat, _fs_erase, _fs_stream
    EXTERN _cur, _mode, _cmdbuf, _cmdlen, _cmdch, _srch, _slen, _sback, _rxpat, _rxanch, _rxlit
    EXTERN _gs, _ge, _glin, _modified, _quitf, _shvalid, _fname, _icase, _ai, _nu, _rowc, _rowa
    EXTERN _m_nofile, _m_nopat, _m_werr
    defc CMDSZ = 64
    defc SRCHSZ = 24
    defc COLS = 80

; ---- helpers
msg:
    push hl
    call _setmsg
    pop bc
    ret
; compare the 0-terminated strings at HL and DE: Z if equal.  DE is left just after its terminator.
streq:
    ld b,0
sq1:
    ld a,(de)
    cp (hl)
    jr z,sq2
    ld b,1
sq2:
    inc de
    or a
    jr z,sq3
    ld a,(hl)
    or a
    jr z,sq1
    inc hl
    jr sq1
sq3:
    ld a,b
    or a
    ret
; copy the string at HL to DE, at most B characters, and terminate it: A = its length
strcp:
    ld c,0
sc1:
    ld a,(hl)
    or a
    jr z,sc2
    ld (de),a
    inc hl
    inc de
    inc c
    djnz sc1
sc2:
    xor a
    ld (de),a
    ld a,c
    ret
; HL -> a pattern: step to the / that ends it (a backslash takes the next character with it), make that a
; terminator, and return HL just after it (or at the end of the string)
skippat:
    ld a,(hl)
    or a
    ret z
    cp '/'
    jr z,sp2
    cp 5Ch
    jr nz,sp1
    inc hl
    ld a,(hl)
    or a
    ret z
sp1:
    inc hl
    jr skippat
sp2:
    ld (hl),0
    inc hl
    ret
; the pattern at HL becomes the one rx_scan uses (a leading ^ anchors it; rxlit = a plain first character, for speed)
rxset:
    xor a
    ld (_rxanch),a
    ld a,(hl)
    cp '^'
    jr nz,rs1
    ld a,1
    ld (_rxanch),a
    inc hl
rs1:
    ld (_rxpat),hl
    ld a,(hl)
    or a
    jr z,rs2
    cp '.'
    jr z,rs2
    cp '['
    jr z,rs2
    cp 5Ch
    jr z,rs2
    cp '$'
    jr z,rs2
    ld c,a
    inc hl
    ld a,(hl)
    cp '*'
    ld a,c
    jr nz,rs3
rs2:
    xor a
rs3:
    ld (_rxlit),a
    ret
; HL = line number of the cursor line / of the last line / of the line at DEHL
curline:
    call ldcur
    jr lnof
lastln:
    call _tx_len
    call dec32
    call _lstart
lnof:
    push de
    push hl
    call _lineno
    pop bc
    pop bc
    ret
; DEHL = start of line HL (1-based)
nthline:
    ld de,0
    push de
    push hl
    call _tx_nthline
    pop bc
    pop bc
    ret
; rx_scan(ex_ls, HL = lo, DE = hi, A = backwards): HL = column of the match; Z if there is none
scan:
    ld (ex_b),a
    ld b,h
    ld c,l
    ld hl,(ex_ls+2)
    push hl
    ld hl,(ex_ls)
    push hl
    push bc
    push de
    ld a,(ex_b)
    call pusha
    call _rx_scan
    pop bc
    pop bc
    pop bc
    pop bc
    pop bc
    ld a,h
    and l
    inc a
    ret
; ex_ls = start of the next line; C if that is still inside the text
ls_next:
    ld hl,(ex_ls)
    ld de,(ex_ls+2)
    call _lend
    call inc32
    ld (ex_ls),hl
    ld (ex_ls+2),de
    call _tx_len
    ld (ex_t),hl
    ld (ex_t+2),de
    ld hl,ex_ls
    ld de,ex_t
    jp cmpm
ls_prev:
    ld hl,(ex_ls)
    ld de,(ex_ls+2)
    call dec32
    call _lstart
    ld (ex_ls),hl
    ld (ex_ls+2),de
    ret

; ---- void dosearch(u8 forward) fastcall
_dosearch:
    ld a,l
    ld (ds_f),a
    ld a,(_slen)
    or a
    jr nz,ds0
    ld hl,s_nosrch
    jp msg
ds0:
    ld hl,_srch
    call rxset
    call _lstartc
    ld (ex_ls),hl
    ld (ex_ls+2),de
    ld (ds_ls0),hl
    ld (ds_ls0+2),de
    ex de,hl
    ld hl,(_cur)
    or a
    sbc hl,de
    ld (ds_c),hl
    ld a,(ds_f)
    or a
    jr z,ds_back
    inc hl                      ; forward: the rest of this line, then the lines below
    ld de,0FFFFh
    xor a
    call scan
ds_f1:
    jp nz,ds_found
    call ls_next
    jr nc,ds_wrap
    ld hl,0
    ld de,0FFFFh
    xor a
    call scan
    jr ds_f1
ds_wrap:                        ; wrap around: from the top down to the cursor
    ld hl,0
    ld (ex_ls),hl
    ld (ex_ls+2),hl
ds_w1:
    call ds_same
    ld de,0FFFFh
    jr nz,ds_w2
    ld de,(ds_c)
ds_w2:
    ld hl,0
    xor a
    call scan
    jr nz,ds_found
    ld hl,ex_ls
    ld de,ds_ls0
    call cmpm
    jr nc,ds_fail
    call ls_next
    jr ds_w1
ds_back:
    ld a,h
    or l
    jr z,ds_b1
    dec hl
    ex de,hl
    ld hl,0
    ld a,1
    call scan
    jr nz,ds_found
ds_b1:
    ld hl,(ex_ls)
    ld a,h
    or l
    ld hl,(ex_ls+2)
    or h
    or l
    jr z,ds_bw
    call ls_prev
    ld hl,0
    ld de,0FFFFh
    ld a,1
    call scan
    jr nz,ds_found
    jr ds_b1
ds_bw:                          ; wrap around: from the bottom up to the cursor
    call _tx_len
    call dec32
    call _lstart
    ld (ex_ls),hl
    ld (ex_ls+2),de
ds_bw1:
    call ds_same
    ld hl,0
    jr nz,ds_bw2
    ld hl,(ds_c)
ds_bw2:
    ld de,0FFFFh
    ld a,1
    call scan
    jr nz,ds_found
    ld hl,ds_ls0
    ld de,ex_ls
    call cmpm
    jr nc,ds_fail
    call ls_prev
    jr ds_bw1
ds_found:
    ld de,ex_ls
    call addm
    jp _sethcur
ds_fail:
    ld hl,_m_nopat
    jp msg
ds_same:                        ; Z if ex_ls is the line the search started on
    ld hl,ex_ls
    ld de,ds_ls0
    jp cmpm

; ---- void cmd_key(u8 k) fastcall
_cmd_key:
    ld a,l
    cp 1Bh
    jr z,ck_n
    cp 0Dh
    jr nz,ck1
    xor a
    ld (_mode),a
    jr runcmd
ck1:
    cp 08h
    jr nz,ck2
    ld a,(_cmdlen)
    or a
    jr z,ck_n
    dec a
    ld (_cmdlen),a
    ret
ck2:
    cp 20h
    ret c
    ld c,a
    ld a,(_cmdlen)
    cp CMDSZ-1
    ret nc
    ld e,a
    ld d,0
    ld hl,_cmdbuf
    add hl,de
    ld (hl),c
    inc a
    ld (_cmdlen),a
    ret
ck_n:
    xor a
    ld (_mode),a
    ret

; ---- run the command line
runcmd:
    ld a,(_cmdlen)
    ld e,a
    ld d,0
    ld hl,_cmdbuf
    add hl,de
    ld (hl),0
    ld a,(_cmdch)
    cp ':'
    jp nz,rc_search
    ld a,(_cmdbuf)
    cp '!'
    jr nz,rc1
    ld hl,_cmdbuf+1
    jp dobang
rc1:
    cp 'r'                      ; :r !cmd - the output of cmd, below the cursor line
    jp nz,rc2
    ld hl,(_cmdbuf+1)
    ld de,' '+'!'*256
    or a
    sbc hl,de
    jr nz,rc2
    ld a,(_cmdlen)
    cp CMDSZ-12
    jr nc,rc2
    ld e,a
    ld d,0
    ld hl,_cmdbuf
    add hl,de
    ex de,hl
    ld hl,s_redir
    ld b,12
    call strcp
    ld hl,_cmdbuf+3
    push hl
    ld hl,0
    push hl
    call _fs_exec
    pop bc
    pop bc
    xor a
    ld (_shvalid),a
    ld a,l
    cp 0FEh
    jr nz,rc1a
    ld hl,s_noe5
    jp msg
rc1a:
    cp 0F0h
    jr nz,rc1b
    ld hl,s_7pg
    jp msg
rc1b:
    ld hl,s_tmp
    call doread
    ld hl,s_tmp
    push hl
    call _fs_erase
    pop bc
    ret
rc_search:                      ; / ?
    sub '?'
    sub 1
    sbc a,a
    and 1
    ld (_sback),a
    ld a,(_cmdlen)
    or a
    jr z,rs9
    cp SRCHSZ+1
    jr c,rs8
    ld a,SRCHSZ
    ld (_cmdlen),a
rs8:
    ld (_slen),a
    ld c,a
    ld b,0
    ld hl,_cmdbuf
    ld de,_srch
    ldir
    xor a
    ld (de),a
rs9:
    ld a,(_sback)
    xor 1
    ld l,a
    jp _dosearch
rc2:
    ld hl,(_cmdbuf)             ; :set option
    ld de,'s'+'e'*256
    or a
    sbc hl,de
    jr nz,rc3
    ld hl,(_cmdbuf+2)
    ld de,'t'+' '*256
    or a
    sbc hl,de
    jr nz,rc3
    ld de,opt_tab
so1:
    ld a,(de)
    or a
    jr z,so3
    ld hl,_cmdbuf+4
    call streq
    jr z,so2
    inc de
    inc de
    inc de
    jr so1
so2:
    ex de,hl
    ld e,(hl)
    inc hl
    ld d,(hl)
    inc hl
    ld a,(hl)
    ld (de),a
    xor a
    ld (_shvalid),a
    ret
so3:
    ld hl,s_unkopt
    jp msg
rc3:
    ld hl,_cmdbuf               ; [range] command
    call prange
    ld a,(hl)
    or a
    jr nz,rc4
    ld a,(ex_na)                ; :N
    or a
    ret z
    ld hl,(ex_l2)
    ld de,0
    jp _gotoline
rc4:
    ld c,a
    inc hl
    ld a,(hl)
    ld b,a                      ; C = command letter, B = the character after it, HL -> that character
    ld a,c
    cp 's'
    jr nz,rc5
    ld a,b
    cp '/'
    jr nz,rc7
    inc hl
    jp dosubst
rc5:
    cp 'd'
    jr nz,rc6
    ld a,b
    or a
    jr nz,rc7
    ld hl,(ex_l1)               ; :[range]d
    call nthline
    ld (_gs),hl
    ld (_gs+2),de
    ld hl,(ex_l2)
    call nthline
    call _lend
    call inc32
    ld (_ge),hl
    ld (_ge+2),de
    call _tx_len
    ld (ex_t),hl
    ld (ex_t+2),de
    ld hl,ex_t
    ld de,_ge
    call cmpm
    jr nc,rc5a
    ld hl,(ex_t)
    ld de,(ex_t+2)
    ld (_ge),hl
    ld (_ge+2),de
rc5a:
    ld a,1
    ld (_glin),a
    ld a,'d'
    jp opa
rc6:
    cp 'g'
    jr z,rc6a
    cp 'v'
    jr nz,rc7
rc6a:
    ld a,b
    cp '/'
    jr nz,rc7
    inc hl
    ld a,c
    sub 'g'
    jp doglobal
rc7:
    ld a,(ex_na)
    or a
    jr z,rc8
    ld hl,s_norange
    jp msg
rc8:
    xor a                       ; command [name]
    ld (ex_name),a
    ld hl,_cmdbuf
r81:
    ld a,(hl)
    or a
    jr z,r85
    cp ' '
    jr z,r82
    inc hl
    jr r81
r82:
    ld (hl),0
r83:
    inc hl
    ld a,(hl)
    cp ' '
    jr z,r83
    ld de,ex_name
    ld b,15
    call strcp
r85:
    ld de,cmd_tab
r86:
    ld a,(de)
    or a
    jr z,c_unk
    ld hl,_cmdbuf
    call streq
    jr z,r87
    inc de
    inc de
    jr r86
r87:
    ex de,hl
    ld a,(hl)
    inc hl
    ld h,(hl)
    ld l,a
    jp (hl)
c_unk:
    ld hl,s_unkcmd
    jp msg
c_r:
    ld hl,ex_name
    jp doread
c_w:
    ld hl,ex_name
c_w1:
    push hl
    call _dosave
    pop bc
    ret
c_wq:
    call c_w
    ld a,(_modified)
    or a
    ret nz
c_qf:
    ld a,1
    ld (_quitf),a
    ret
c_e:
    ld a,(_cmdbuf+1)
    or a
    jr nz,ce1
    ld a,(_modified)
    or a
    jr z,ce1
    ld hl,s_unse
    jp msg
ce1:
    ld a,(ex_name)
    or a
    jr nz,ce2
    ld hl,_fname
    ld de,ex_name
    ld b,15
    call strcp
ce2:
    ld a,(ex_name)
    or a
    jr nz,ce3
    ld hl,_m_nofile
    jp msg
ce3:
    ld hl,ex_name
    push hl
    call _ed_load
    pop bc
    ret
c_q:
    ld a,(_modified)
    or a
    jr z,c_qf
    ld hl,s_unsq
    jp msg

; ---- [N|.|$][,[N|.|$]] or % at HL: ex_l1, ex_l2 = the line numbers, ex_na = how many were given; HL -> what follows
prange:
    ld (pr_q0),hl
    xor a
    ld (ex_na),a
    ld (pr_i),a
    push hl
    call curline
    ld (ex_l1),hl
    ld (ex_l2),hl
    pop hl
    ld a,(hl)
    cp '%'
    jr nz,pr2
    inc hl
    push hl
    call lastln
    ld (ex_l2),hl
    ld hl,1
    ld (ex_l1),hl
    pop hl
    ld a,2
    ld (ex_na),a
    jr pr9
pr2:
    ld a,(hl)
    cp '$'
    jr nz,pr3
    inc hl
    push hl
    call lastln
    ex de,hl
    pop hl
    jr pr6
pr3:
    ld de,(ex_l1)
    cp '.'
    jr nz,pr4
    inc hl
    jr pr6
pr4:
    sub '0'
    cp 10
    jr nc,pr6                   ; nothing here: the first line stands in
    ld de,0
pr5:
    ld a,(hl)
    sub '0'
    cp 10
    jr nc,pr6
    push hl
    ld h,d
    ld l,e
    add hl,hl
    add hl,hl
    add hl,de
    add hl,hl
    ld e,a
    ld d,0
    add hl,de
    ex de,hl
    pop hl
    inc hl
    jr pr5
pr6:
    ld a,(pr_i)
    or a
    jr nz,pr7
    ld (ex_l1),de
    ld (ex_l2),de
    ld a,(hl)
    cp ','
    jr z,pr6a
    ld de,(pr_q0)
    push hl
    or a
    sbc hl,de
    pop hl
    jr z,pr9
    ld a,1
    ld (ex_na),a
    jr pr9
pr6a:
    inc hl
    ld a,1
    ld (pr_i),a
    inc a
    ld (ex_na),a
    jr pr2
pr7:
    ld (ex_l2),de
pr9:
    push hl
    ld hl,(ex_l2)
    ld de,(ex_l1)
    or a
    sbc hl,de
    jr nc,pr10
    ld hl,(ex_l2)
    ld (ex_l1),hl
    ld (ex_l2),de
pr10:
    ld hl,(ex_l1)
    ld a,h
    or l
    jr nz,pr11
    inc hl
    ld (ex_l1),hl
pr11:
    pop hl
    ret

; ---- :g/pat/cmd  :v/pat/cmd  (HL -> pat, A != 0 for :v) - the lines are visited from the bottom up
doglobal:
    ld (dg_inv),a
    ld (dg_a),hl
    call skippat
    ld (dg_q),hl
    ld de,(dg_a)
    ld a,(de)
    or a
    jr z,dg_bad
    ld a,(hl)
    or a
    jr z,dg_bad
    cp 'g'
    jr z,dg_bad
    cp 'v'
    jr nz,dg1
dg_bad:
    ld hl,s_badg
    jp msg
dg1:
    ex de,hl
    ld de,_srch
    ld b,SRCHSZ
    call strcp
    ld (_slen),a
    ld hl,(dg_q)
    ld de,ex_gsub
    ld b,31
    call strcp
    ld (dg_n),a
    ld hl,1
    ld (dg_lo),hl
    ld a,(ex_na)
    or a
    jr z,dg1a
    ld hl,(ex_l1)
    ld (dg_lo),hl
    ld hl,(ex_l2)
    jr dg1b
dg1a:
    call lastln
dg1b:
    ld (dg_k),hl
dg2:
    ld hl,(dg_k)
    ld a,h
    or l
    ret z
    ld de,(dg_lo)
    or a
    sbc hl,de
    ret c
    ld hl,(dg_k)
    call nthline
    ld (ex_ls),hl
    ld (ex_ls+2),de
    ld hl,_srch
    call rxset
    xor a
    ld (_rxlit),a
    ld h,a
    ld l,a
    ld de,0FFFFh
    call scan
    ld b,0
    jr z,dg3
    inc b
dg3:
    ld a,(dg_inv)
    or a
    jr z,dg4
    ld a,1
dg4:
    cp b
    jr z,dg8
    ld hl,(ex_ls)
    ld de,(ex_ls+2)
    call stcur
    ld hl,ex_gsub
    ld de,_cmdbuf
    ld b,31
    call strcp
    ld (_cmdlen),a
    ld a,':'
    ld (_cmdch),a
    call runcmd
    ld a,(_quitf)
    or a
    ret nz
dg8:
    ld hl,(dg_k)
    dec hl
    ld (dg_k),hl
    jr dg2

; ---- :[range]s/pat/rep/[g]  (HL -> pat; pat is a regular expression, rep is literal with & = the match; one undo group)
dosubst:
    ld (sb_pat),hl
    call skippat
    ld (sb_rep),hl
    ld b,0
sb1:
    ld a,(hl)
    or a
    jr z,sb2
    cp '/'
    jr z,sb2
    inc hl
    inc b
    jr sb1
sb2:
    ld a,b
    ld (sb_rl),a
    xor a
    ld (sb_g),a
    ld (sb_n),a
    ld a,(hl)
    cp '/'
    jr nz,sb3
    ld (hl),0
    inc hl
    ld a,(hl)
    cp 'g'
    jr nz,sb3
    ld a,1
    ld (sb_g),a
sb3:
    ld hl,(sb_pat)
    ld a,(hl)
    or a
    jr nz,sb4
    ld a,(_slen)                ; :s//x/ uses the last pattern
    or a
    jr z,sb3a
    ld hl,_srch
    ld a,(hl)
    or a
    jr nz,sb4
sb3a:
    ld hl,s_emptyp
    jp msg
sb4:
    call rxset
    xor a
    ld (_rxlit),a
    ld hl,(ex_l2)               ; the lines ex_l1 .. ex_l2
    ld de,(ex_l1)
    or a
    sbc hl,de
    inc hl
    ld (sb_cnt),hl
    ex de,hl
    call nthline
    ld (ex_ls),hl
    ld (ex_ls+2),de
    ld (sb_last),hl
    ld (sb_last+2),de
sb5:
    ld hl,0
    ld (sb_p),hl
sb6:
    ld hl,(sb_p)                ; the next match on this line
    ld de,0FFFFh
    xor a
    call scan
    jp z,sb_next
    ld (sb_p),hl
    ld hl,(_rxpat)
    push hl
    ld hl,(sb_p)
    push hl
    call _mhere
    pop bc
    pop bc
    ld de,(sb_p)
    or a
    sbc hl,de
    jr nz,sb7
    inc de                      ; an empty match does not count
    ld (sb_p),de
    jr sb6
sb7:
    ld (sb_m),hl
    ld de,COLS+1
    or a
    sbc hl,de
    add hl,de
    jr c,sb7a
    ld hl,COLS
sb7a:
    ld (sb_t),hl
    ld hl,_rowc                 ; the matched text -> rowc (for &)
    push hl
    ld hl,(sb_p)
    ld de,ex_ls
    call addm
    ld (sb_at),hl
    ld (sb_at+2),de
    push de
    push hl
    ld hl,0
    push hl
    ld hl,(sb_t)
    push hl
    call _tx_read
    pop bc
    pop bc
    pop bc
    pop bc
    pop bc
    ld hl,0                     ; build the replacement in rowa
    ld (sb_rl2),hl
    xor a
    ld (sb_i),a
sb8:
    ld a,(sb_i)
    ld hl,sb_rl
    cp (hl)
    jr nc,sb12
    ld e,a
    ld d,0
    ld hl,(sb_rep)
    add hl,de
    ld a,(hl)
    cp '&'
    jr nz,sb10
    ld hl,COLS
    ld de,(sb_rl2)
    or a
    sbc hl,de
    ld de,(sb_m)
    or a
    sbc hl,de
    jr nc,sb9
    ld hl,s_replong
    call msg
    jp sb_done
sb9:
    ld hl,(sb_rl2)
    ld de,_rowa
    add hl,de
    ex de,hl
    ld hl,_rowc
    ld bc,(sb_m)
    ldir
    ld hl,(sb_rl2)
    ld de,(sb_m)
    add hl,de
    ld (sb_rl2),hl
    jr sb11
sb10:
    cp 5Ch                      ; \& = a literal &
    jr nz,sb10a
    inc hl
    ld a,(hl)
    cp '&'
    ld a,5Ch
    jr nz,sb10a
    ld hl,sb_i
    inc (hl)
    ld a,'&'
sb10a:
    ld c,a
    ld hl,(sb_rl2)
    ld de,_rowa
    add hl,de
    ld (hl),c
    ld hl,(sb_rl2)
    inc hl
    ld (sb_rl2),hl
sb11:
    ld hl,sb_i
    inc (hl)
    jr sb8
sb12:
    ld hl,(sb_at+2)
    push hl
    ld hl,(sb_at)
    push hl
    ld hl,0
    push hl
    ld hl,(sb_m)
    push hl
    call _tdel
    pop bc
    pop bc
    pop bc
    pop bc
    ld hl,(sb_rl2)
    ld a,h
    or l
    jr z,sb13
    ld hl,(sb_at+2)
    push hl
    ld hl,(sb_at)
    push hl
    ld hl,_rowa
    push hl
    ld hl,0
    push hl
    ld hl,(sb_rl2)
    push hl
    call _tinsn
    pop bc
    pop bc
    pop bc
    pop bc
    pop bc
    ld a,l
    or a
    jr z,sb_done
sb13:
    ld hl,(sb_p)
    ld de,(sb_rl2)
    add hl,de
    ld (sb_p),hl
    ld a,1
    ld (sb_n),a
    ld hl,(ex_ls)
    ld (sb_last),hl
    ld hl,(ex_ls+2)
    ld (sb_last+2),hl
    ld a,(sb_g)                 ; without g, or with ^, one per line
    or a
    jr z,sb_next
    ld a,(_rxanch)
    or a
    jp z,sb6
sb_next:
    ld hl,(sb_cnt)
    dec hl
    ld (sb_cnt),hl
    ld a,h
    or l
    jr z,sb_done
    call ls_next
    jp c,sb5
sb_done:
    ld a,(sb_n)
    or a
    jr nz,sb_ok
    ld hl,_m_nopat
    jp msg
sb_ok:
    ld hl,(sb_last)
    ld de,(sb_last+2)
    call _sethcur
    ld hl,s_subst
    jp msg

; ---- :r file  (HL -> name) - insert the file below the cursor line
doread:
    ld a,(hl)
    or a
    jr nz,rd1
    ld hl,_m_nofile
    jp msg
rd1:
    push hl
    call _lendc
    call inc32
    ld (rd_at),hl
    ld (rd_at+2),de
    ld (rd_at0),hl
    ld (rd_at0+2),de
    ld a,10
    ld (rd_last),a
    ld hl,rsink
    push hl
    call _fs_stream
    pop bc
    pop bc
    ld a,h
    or a
    jr nz,rd2
    ld a,l
    dec a
    jr nz,rd2
    ld hl,s_cantopen
    jp msg
rd2:
    ld a,(rd_last)              ; a last line without a line break gets one
    cp 10
    jr z,rd3
    ld hl,(rd_at+2)
    push hl
    ld hl,(rd_at)
    push hl
    ld hl,s_lf
    push hl
    ld hl,0
    push hl
    inc hl
    push hl
    call _tinsn
    pop bc
    pop bc
    pop bc
    pop bc
    pop bc
rd3:
    ld hl,rd_at0
    ld de,rd_at
    call cmpm
    ret nc                      ; nothing was read
    ld hl,(rd_at0)
    ld de,(rd_at0+2)
    call stcur
    call _clampcur
    jp _setwant
; int rsink(const u8 *b, u8 n) : called by fs_stream for each chunk of the file
rsink:
    ld hl,2
    add hl,sp
    ld a,(hl)
    ld (rd_n),a
    inc hl
    inc hl
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld (rd_b),de
    ld hl,(rd_at+2)
    push hl
    ld hl,(rd_at)
    push hl
    push de
    ld hl,0
    push hl
    ld l,a
    push hl
    call _tinsn
    pop bc
    pop bc
    pop bc
    pop bc
    pop bc
    ld a,l
    or a
    jr nz,rk1
    ld h,a
    ld l,a
    ret
rk1:
    ld a,(rd_n)
    ld l,a
    ld h,0
    ld de,rd_at
    call addm
    ld (rd_at),hl
    ld (rd_at+2),de
    ld hl,(rd_b)
    ld a,(rd_n)
    ld e,a
    ld d,0
    add hl,de
    dec hl
    ld a,(hl)
    ld (rd_last),a
    ld hl,1
    ret

; ---- :!cmd  (HL -> cmd) - run it with the OS (E5h); on an OS without that: save, leave a batch file for V.BAT, quit
dobang:
    ld (dg_a),hl
    push hl
    ld hl,1
    push hl
    call _fs_exec
    pop bc
    pop bc
    ld a,l
    cp 0FEh
    jr z,db1
    xor a
    ld (_shvalid),a
    ld a,l
    cp 0F0h
    ret nz
    ld hl,s_7pg
    jp msg
db1:
    ld a,(_fname)
    or a
    jr nz,db2
    ld hl,_m_nofile
    jp msg
db2:
    ld a,(_modified)
    or a
    jr z,db3
    ld hl,s_empty
    call c_w1
    ld a,(_modified)
    or a
    ret nz
db3:
    ld hl,(dg_a)
    push hl
    ld hl,_fname
    push hl
    call curline
    push hl
    call _fs_bat
    pop bc
    pop bc
    pop bc
    ld a,h
    or l
    jp z,c_qf
    ld hl,_m_werr
    jp msg

; ---- tables and messages
; :set options: name, variable, value
opt_tab:
    defm "ic"
    defb 0
    defw _icase
    defb 1
    defm "ignorecase"
    defb 0
    defw _icase
    defb 1
    defm "noic"
    defb 0
    defw _icase
    defb 0
    defm "noignorecase"
    defb 0
    defw _icase
    defb 0
    defm "ai"
    defb 0
    defw _ai
    defb 1
    defm "autoindent"
    defb 0
    defw _ai
    defb 1
    defm "noai"
    defb 0
    defw _ai
    defb 0
    defm "noautoindent"
    defb 0
    defw _ai
    defb 0
    defm "nu"
    defb 0
    defw _nu
    defb 1
    defm "number"
    defb 0
    defw _nu
    defb 1
    defm "nonu"
    defb 0
    defw _nu
    defb 0
    defm "nonumber"
    defb 0
    defw _nu
    defb 0
    defb 0
; commands: name, handler
cmd_tab:
    defm "w"
    defb 0
    defw c_w
    defm "q"
    defb 0
    defw c_q
    defm "wq"
    defb 0
    defw c_wq
    defm "x"
    defb 0
    defw c_wq
    defm "q!"
    defb 0
    defw c_qf
    defm "r"
    defb 0
    defw c_r
    defm "e"
    defb 0
    defw c_e
    defm "e!"
    defb 0
    defw c_e
    defb 0
s_redir: defm " >VIMI.TMP"
    defb 0
s_tmp:  defm "VIMI.TMP"
s_empty: defb 0
s_lf:   defb 10
s_nosrch: defm "no search"
    defb 0
s_noe5: defm "needs LSX with E5h"
    defb 0
s_7pg:  defm "need 7 free pages: ramdisk 64"
    defb 0
s_unkopt: defm "unknown option"
    defb 0
s_norange: defm "range not allowed"
    defb 0
s_unkcmd: defm "unknown command"
    defb 0
s_unse: defm "unsaved (use e!)"
    defb 0
s_unsq: defm "unsaved (use q!)"
    defb 0
s_badg: defm "bad :g"
    defb 0
s_emptyp: defm "empty pattern"
    defb 0
s_replong: defm "rep too long"
    defb 0
s_subst: defm "substituted"
    defb 0
s_cantopen: defm "can't open file"
    defb 0

    SECTION bss_user
ex_ls:  defs 4
ex_t:   defs 4
ex_l1:  defs 2
ex_l2:  defs 2
ex_na:  defb 0
ex_b:   defb 0
ex_name: defs 16
ex_gsub: defs 32
pr_q0:  defs 2
pr_i:   defb 0
ds_f:   defb 0
ds_c:   defs 2
ds_ls0: defs 4
dg_inv: defb 0
dg_n:   defb 0
dg_a:   defs 2
dg_q:   defs 2
dg_k:   defs 2
dg_lo:  defs 2
sb_pat: defs 2
sb_rep: defs 2
sb_rl:  defb 0
sb_g:   defb 0
sb_n:   defb 0
sb_i:   defb 0
sb_cnt: defs 2
sb_p:   defs 2
sb_m:   defs 2
sb_t:   defs 2
sb_rl2: defs 2
sb_at:  defs 4
sb_last: defs 4
rd_at:  defs 4
rd_at0: defs 4
rd_b:   defs 2
rd_n:   defb 0
rd_last: defb 0
