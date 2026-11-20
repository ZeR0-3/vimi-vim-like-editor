; file_z80.asm - load, save, init (the asm twin of core/ed_file.c and of ed_quit; -DM_ASM)
    SECTION code_user
    PUBLIC _ed_init, _ed_load, _dosave, _ed_goto, _ed_redraw, _ed_quit, _matchpos
    EXTERN _matchb, _lendc
    EXTERN dec32, inc32, _gotoline, _setmsg, _putnum, _mins
    EXTERN _tx_reset, _tx_adopt, _tx_cap, _tx_len, _tx_load_chunk, _st_get, _st_put, _fs_load, _fs_save
    EXTERN _cur, _want, _top, _left, _mode, _count, _pend, _pg, _ptob, _pcount, _modified, _quitf, _shvalid
    EXTERN _fname, _msg, _lc_pos, _lc_line, _mk, _reg, _pq, _rlen, _rtop, _mrc, _inmac, _mlast, _ai
    EXTERN _lastlen, _ylin, _ylen, _slen, _cmdlen, _icnt, _u_n, _u_dn, _ud, _m_nofile, _m_werr

; pos_t matchpos(void) : the bracket matching the one at / after the cursor on this line (matchb is in nav_z80.asm)
_matchpos:
    ld hl,(_cur+2)
    push hl
    ld hl,(_cur)
    push hl
    call _lendc
    push de
    push hl
    call _tx_len
    push de
    push hl
    call _matchb
    ld b,h
    ld c,l
    ld hl,12
    add hl,sp
    ld sp,hl
    ld h,b
    ld l,c
    ret

_ed_quit:
    ld a,(_quitf)
    ld l,a
    ld h,0
    ret
_ed_redraw:
    xor a
    ld (_shvalid),a
    ret
_ed_goto:
    ld hl,2
    add hl,sp
    ld a,(hl)
    inc hl
    ld h,(hl)
    ld l,a
    ld de,0
    jp _gotoline

; cursor and view to the top, nothing modified, no undo history, no marks
rstv:
    ld hl,0
    ld (_cur),hl
    ld (_cur+2),hl
    ld (_want),hl
    ld (_top),hl
    ld (_top+2),hl
    ld (_left),hl
    ld (_lc_pos),hl
    ld (_lc_pos+2),hl
    ld (_lc_line+2),hl
    ld (_u_n),hl
    ld (_u_dn),hl
    ld (_u_dn+2),hl
    ld (_ud),hl
    ld (_ud+2),hl
    inc hl
    ld (_lc_line),hl
    xor a
    ld (_modified),a
    ld (_shvalid),a
    ld (_mode),a
    ld (_quitf),a
    ld hl,_mk
    ld de,_mk+1
    ld (hl),0FFh
    ld bc,27*4-1
    ldir
    ret
; fname = the name at fl_name (15 characters at most)
cpname:
    ld hl,_fname
    ld de,_fname+1
    ld (hl),0
    ld bc,15
    ldir
    ld hl,(fl_name)
    ld de,_fname
    ld b,15
cn1:
    ld a,(hl)
    or a
    ret z
    ld (de),a
    inc hl
    inc de
    djnz cn1
    ret
msg:
    push hl
    call _setmsg
    pop bc
    ret

; void ed_init(void) : an empty buffer (one empty line), everything reset
_ed_init:
    call _tx_reset
    ld hl,0
    push hl
    push hl
    ld hl,s_lf
    push hl
    ld hl,0
    push hl
    inc hl
    push hl
    call _mins
    pop bc
    pop bc
    pop bc
    pop bc
    pop bc
    call rstv
    xor a
    ld (_pend),a
    ld (_pg),a
    ld (_ptob),a
    ld (_fname),a
    ld (_msg),a
    ld (_reg),a
    ld (_pq),a
    ld (_mrc),a
    ld (_inmac),a
    ld (_mlast),a
    ld (_ai),a
    ld (_lastlen),a
    ld (_ylin),a
    ld (_slen),a
    ld (_cmdlen),a
    ld h,a
    ld l,a
    ld (_count),hl
    ld (_pcount),hl
    ld (_rtop),hl
    ld (_ylen),hl
    ld (_icnt),hl
    ld hl,_rlen
    ld de,_rlen+1
    ld (hl),a
    ld bc,26*2-1
    ldir
    ret

; int ed_load(const char *name) : 0 = loaded, 1 = new file, 2 = too big
_ed_load:
    ld hl,2
    add hl,sp
    ld a,(hl)
    inc hl
    ld h,(hl)
    ld l,a
    ld (fl_name),hl
    call cpname
    call _tx_cap
    call dec32
    ld bc,(fl_name)
    push bc
    push de
    push hl
    call _fs_load
    pop bc
    pop bc
    pop bc
    ld (fl_n),hl
    ld (fl_n+2),de
    ld a,d
    and e
    and h
    inc a
    jr nz,el3
    ld a,l
    cp 0FEh
    jr nz,el1
    call _ed_init               ; too big for the store
    ld hl,s_toobig
    call msg
    ld hl,2
    ret
el1:
    inc a
    jr nz,el3
    call _ed_init               ; no such file: a new one with this name
    call cpname
    ld hl,s_newfile
    call msg
    ld hl,1
    ret
el3:
    ld hl,(fl_n)                ; the text must end with a line break
    ld de,(fl_n+2)
    ld a,h
    or l
    or d
    or e
    jr z,el4
    call dec32
    push de
    push hl
    call _st_get
    pop bc
    pop bc
    ld a,l
    cp 10
    jr z,el5
el4:
    ld hl,(fl_n+2)
    push hl
    ld hl,(fl_n)
    push hl
    ld hl,s_lf
    push hl
    ld hl,1
    push hl
    call _tx_load_chunk
    pop bc
    pop bc
    pop bc
    pop bc
    ld hl,(fl_n+2)
    push hl
    ld hl,(fl_n)
    push hl
    ld hl,10
    push hl
    call _st_put
    pop bc
    pop bc
    pop bc
    ld hl,(fl_n)
    ld de,(fl_n+2)
    call inc32
    ld (fl_n),hl
    ld (fl_n+2),de
el5:
    ld hl,(fl_n+2)
    push hl
    ld hl,(fl_n)
    push hl
    call _tx_adopt
    pop bc
    pop bc
    call rstv
    ld hl,0
    ret

; void dosave(const char *name) : :w [name]  ("" = the current name)
_dosave:
    ld hl,2
    add hl,sp
    ld a,(hl)
    inc hl
    ld h,(hl)
    ld l,a
    ld a,(hl)
    or a
    jr nz,sv1
    ld hl,_fname
    ld a,(hl)
    or a
    jr nz,sv1
    ld hl,_m_nofile
    jp msg
sv1:
    ld (fl_name),hl
    push hl
    call _tx_len
    push de
    push hl
    call _fs_save
    pop bc
    pop bc
    pop bc
    ld a,h
    or l
    jr z,sv2
    ld hl,_m_werr
    jp msg
sv2:
    ld (_modified),a
    ld a,(_fname)
    or a
    call z,cpname
    ld hl,s_written
    call msg
    ld hl,_msg+8
    push hl
    call _tx_len
    push de
    push hl
    ld hl,fl_w
    push hl
    call _putnum
    pop bc
    pop bc
    pop bc
    pop bc
    ld a,(fl_w)
    ld e,a
    ld d,0
    ld hl,_msg+8
    add hl,de
    ld (hl),0
    ret

s_lf:   defb 10
s_toobig: defm "too big (ramdisk 64)"
    defb 0
s_newfile: defm "[New File]"
    defb 0
s_written: defm "written "
    defb 0

    SECTION bss_user
fl_name: defs 2
fl_n:   defs 4
fl_w:   defb 0
