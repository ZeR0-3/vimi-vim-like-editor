; sys_z80.asm - the system layer (asm twins of hal/store_mz2500.c, hal/store_file.c (stf_init / stf_cap / stf_exit),
; hal/fs_bdos.c, hal/hal_mz2500.c and z80/vimi_main.c; the Z80 build no longer compiles those files).
;   store : st_* dispatch to the page / plain-memory store (store_z80.asm, st_mem 0 / 1) or the swap file (st_mem 2)
;   files : CP/M BDOS, text as CRLF lines ended by ^Z
;   main  : VIMI [-n] [-sD[KB]] [+N] [file]
    SECTION code_user
    PUBLIC _main
    PUBLIC _st_select, _st_init, _st_exit, _st_cap, _st_get, _st_put, _st_read, _st_write, _st_move
    PUBLIC _st_findb, _st_rfindb, _st_countb, _stf_init, _stf_cap, _stf_exit
    PUBLIC _fs_stream, _fs_load, _fs_save, _fs_erase, _fs_bat, _fs_exec
    PUBLIC _hal_init, _hal_exit, _hal_clear, _hal_getkey, _hal_scroll, _hal_putrow
    PUBLIC _hw_start, _rw_adr, _rw_chars, _rw_attrs
    EXTERN _st_init_asm, _st_exit_asm, _st_get_asm, _st_capv, _st_mem, _st_close, _st_saveorig
    EXTERN _sv_off, _sv_ptr, _sv_n, _sv_res, _sv_c, _sv_read, _sv_write, _sv_findb, _sv_rfindb, _sv_countb
    EXTERN _stf_get, _stf_read, _stf_write, _stf_findb, _stf_rfindb, _stf_countb, _sblk, _sdirty, _sfcb, _rr, _lasti
    EXTERN _tx_load_begin, _tx_load_chunk, _tx_read
    EXTERN _vram_row, _crtc_start, _vram_clear, _kbd_get, _kbd_install, _kbd_remove, _pal_on, _pal_off, _pal_enable
    EXTERN _exec_ok, _exec_call
    EXTERN _ed_init, _ed_load, _ed_goto, _ed_quit, _ed_render, _ed_key
    defc BDOS = 5

pop5:
    pop bc
    pop bc
    pop bc
    pop bc
    pop bc
    ret
; DEHL = the 32 bit value at HL
ld32:
    ld e,(hl)
    inc hl
    ld d,(hl)
    inc hl
    ld a,(hl)
    inc hl
    ld h,(hl)
    ld l,a
    ex de,hl
    ret
; flags of (HL) - (DE), 32 bit unsigned (Z equal, C if less)
cmp32:
    inc hl
    inc hl
    inc hl
    inc de
    inc de
    inc de
    ld b,4
c32a:
    ld a,(de)
    ld c,a
    ld a,(hl)
    cp c
    ret nz
    dec hl
    dec de
    djnz c32a
    ret
; (HL) += BC / (HL) -= BC, 32 bit
add32:
    ld a,(hl)
    add a,c
    ld (hl),a
    inc hl
    ld a,(hl)
    adc a,b
    ld (hl),a
    inc hl
    ld a,(hl)
    adc a,0
    ld (hl),a
    inc hl
    ld a,(hl)
    adc a,0
    ld (hl),a
    ret
sub32:
    ld a,(hl)
    sub c
    ld (hl),a
    inc hl
    ld a,(hl)
    sbc a,b
    ld (hl),a
    inc hl
    ld a,(hl)
    sbc a,0
    ld (hl),a
    inc hl
    ld a,(hl)
    sbc a,0
    ld (hl),a
    ret

; ================================================================ store
; void st_select(char d, u16 kb) : use a swap file on drive d (kb KB, at most 128; 0 = 60) instead of the RAM pages
_st_select:
    ld hl,2
    add hl,sp
    ld e,(hl)
    inc hl
    ld d,(hl)
    inc hl
    ld a,(hl)
    ld (st_drv),a
    ld hl,128
    or a
    sbc hl,de
    jr nc,ss1
    ld de,128
ss1:
    ld (st_kb),de
    ret
_st_init:
    ld a,(st_drv)
    or a
    jr z,si1
    ld l,a
    ld h,0
    push hl
    ld hl,(st_kb)
    push hl
    call _stf_init
    pop bc
    pop bc
    ld a,l
    or a
    ret nz
si1:
    jp _st_init_asm
_st_exit:
    ld a,(_st_mem)
    cp 2
    call z,_stf_exit
    jp _st_exit_asm
_st_cap:
    ld a,(_st_mem)
    cp 2
    jr z,_stf_cap
    ld hl,(_st_capv)
    ld de,0
    ret
_stf_cap:
    ld hl,(sf_cap)
    ld de,(sf_cap+2)
    ret
; u8 st_get(pos_t i)
_st_get:
    ld a,(_st_mem)
    cp 2
    jp nc,_stf_get
    ld hl,2
    add hl,sp
    ld a,(hl)
    inc hl
    ld h,(hl)
    ld l,a
    jp _st_get_asm
; void st_read(u8 *dst, pos_t src, pos_t n)
_st_read:
    ld a,(_st_mem)
    cp 2
    jp nc,_stf_read
    ld hl,2
    add hl,sp
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld (_sv_n),de
    inc hl
    inc hl
    inc hl
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld (_sv_off),de
    inc hl
    inc hl
    inc hl
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld (_sv_ptr),de
    jp _sv_read
; void st_write(pos_t dst, const u8 *src, pos_t n)
_st_write:
    ld a,(_st_mem)
    cp 2
    jp nc,_stf_write
    ld hl,2
    add hl,sp
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld (_sv_n),de
    inc hl
    inc hl
    inc hl
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld (_sv_ptr),de
    inc hl
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld (_sv_off),de
    jp _sv_write
; void st_put(pos_t i, u8 c)
_st_put:
    ld hl,2
    add hl,sp
    ld a,(hl)
    ld (st_one),a
    inc hl
    inc hl
    call ld32
    push de
    push hl
    ld hl,st_one
    push hl
    ld hl,0
    push hl
    inc hl
    push hl
    call _st_write
    jp pop5
; void st_move(pos_t dst, pos_t src, pos_t n) : memmove inside the store, through a 128-byte buffer
_st_move:
    ld hl,2
    add hl,sp
    ld de,mv_n
    ld bc,12
    ldir
    ld hl,mv_d
    ld de,mv_s
    call cmp32
    ret z
    jr nc,mvb
mvf:                            ; dst < src: front to back
    call mv_k
    ret z
    ld hl,(mv_s)
    ld de,(mv_s+2)
    call mv_rd
    ld hl,(mv_d)
    ld de,(mv_d+2)
    call mv_wr
    ld bc,(mv_kk)
    ld hl,mv_s
    call add32
    ld hl,mv_d
    call add32
    ld hl,mv_n
    call sub32
    jr mvf
mvb:                            ; dst > src: back to front
    call mv_k
    ret z
    ld hl,mv_n
    call sub32
    ld hl,mv_s
    call mv_at
    call mv_rd
    ld hl,mv_d
    call mv_at
    call mv_wr
    jr mvb
; BC = mv_kk = min(mv_n, 128); Z if nothing is left
mv_k:
    ld hl,(mv_n)
    ld de,(mv_n+2)
    ld a,d
    or e
    or h
    jr nz,mk1
    ld a,l
    or a
    ret z
    cp 129
    jr c,mk2
mk1:
    ld a,128
mk2:
    ld c,a
    ld b,0
    ld (mv_kk),bc
    or a
    ret
; DEHL = (HL) + mv_n
mv_at:
    call ld32
    ld bc,(mv_n)
    add hl,bc
    ex de,hl
    ld bc,(mv_n+2)
    adc hl,bc
    ex de,hl
    ret
mv_rd:                          ; st_read(bounce, DEHL, mv_kk)
    ld bc,st_bounce
    push bc
    push de
    push hl
    ld hl,0
    push hl
    ld hl,(mv_kk)
    push hl
    call _st_read
    jp pop5
mv_wr:                          ; st_write(DEHL, bounce, mv_kk)
    push de
    push hl
    ld hl,st_bounce
    push hl
    ld hl,0
    push hl
    ld hl,(mv_kk)
    push hl
    call _st_write
    jp pop5

; fb_c / fb_e / fb_o = the arguments (off, end-or-floor, c) of the scans below; C set if off < e
fb_args:
    ld hl,4
    add hl,sp
    ld de,fb_c
    ld bc,10
    ldir
    ld hl,fb_o
    ld de,fb_e
    jp cmp32
; pos_t st_findb(pos_t off, pos_t end, u8 c) : first c in [off, end), or end
_st_findb:
    call fb_args
    jr c,fb1
fb_end:
    ld hl,(fb_e)
    ld de,(fb_e+2)
    ret
fb1:
    ld a,(_st_mem)
    cp 2
    jp nc,_stf_findb
    call fb_set
    call _sv_findb
    ld hl,(_sv_res)
    ld a,h
    and l
    inc a
    jr z,fb_end
    ld de,0
    ret
; sv_off = off, sv_n = end - off, sv_c = c
fb_set:
    ld hl,(fb_o)
    ld (_sv_off),hl
    ex de,hl
    ld hl,(fb_e)
    or a
    sbc hl,de
    ld (_sv_n),hl
    ld a,(fb_c)
    ld (_sv_c),a
    ret
; pos_t st_countb(pos_t off, pos_t end, u8 c)
_st_countb:
    call fb_args
    jr c,cb1
    ld hl,0
    ld d,h
    ld e,l
    ret
cb1:
    ld a,(_st_mem)
    cp 2
    jp nc,_stf_countb
    call fb_set
    call _sv_countb
    ld hl,(_sv_res)
    ld de,0
    ret
; pos_t st_rfindb(pos_t off, pos_t floor, u8 c) : last c in [floor, off), or POS_NONE
_st_rfindb:
    call fb_args
    jr z,rf_none
    jr nc,rf1
rf_none:
    ld hl,0FFFFh
    ld d,h
    ld e,l
    ret
rf1:
    ld a,(_st_mem)
    cp 2
    jp nc,_stf_rfindb
    ld hl,(fb_o)
    ld de,(fb_e)
    push hl
    or a
    sbc hl,de
    ld (_sv_n),hl
    pop hl
    dec hl
    ld (_sv_off),hl
    ld a,(fb_c)
    ld (_sv_c),a
    call _sv_rfindb
    ld hl,(_sv_res)
    ld a,h
    and l
    inc a
    jr z,rf_none
    ld de,0
    ret

; ---- the swap file: VIMISWP.TMP on the chosen drive, pre-allocated; 4 cache blocks at A000h (store_file_z80.asm)
sf_bdos:                        ; BDOS function C on the swap file's FCB
    ld de,_sfcb
    jp BDOS
; u8 stf_init(char d, u16 kb) : 1 = the swap-file store is in use
_stf_init:
    ld hl,2
    add hl,sp
    ld e,(hl)
    inc hl
    ld d,(hl)
    inc hl
    ld a,(hl)
    cp 'a'
    jr c,sf1
    cp 'z'+1
    jr nc,sf1
    sub 32
sf1:
    sub 'A'-1
    ld (sf_d),a
    ld a,d
    or e
    jr nz,sf2
    ld de,60
sf2:
    ld hl,1023
    or a
    sbc hl,de
    jr nc,sf3
    ld de,1023
sf3:
    ld (sf_kb),de
    ld hl,_sfcb
    ld de,_sfcb+1
    ld (hl),0
    ld bc,35
    ldir
    ld hl,sf_name
    ld de,_sfcb+1
    ld bc,11
    ldir
    ld a,(sf_d)
    ld (_sfcb),a
    ld c,19                     ; delete an old one
    call sf_bdos
    ld hl,_sfcb+12
    ld de,_sfcb+13
    ld (hl),0
    ld bc,23
    ldir
    ld c,22                     ; make
    call sf_bdos
    inc a
    jr z,sf_no
    ld hl,0A000h
    ld de,0A001h
    ld (hl),0
    ld bc,127
    ldir
    ld c,26
    ld de,0A000h
    call BDOS
    ld hl,(sf_kb)               ; pre-allocate: a full disk fails now, not in the middle of editing
    add hl,hl
    add hl,hl
    add hl,hl
sf4:
    ld (sf_r),hl
    ld a,h
    or l
    jr z,sf5
    ld c,21
    call sf_bdos
    or a
    jr nz,sf_full
    ld hl,(sf_r)
    dec hl
    jr sf4
sf_full:
    call _stf_exit
sf_no:
    ld hl,0
    ret
sf5:
    ld hl,_sblk
    ld b,8
sf6:
    ld (hl),0FFh
    inc hl
    djnz sf6
    ld hl,0
    ld (_sdirty),hl
    ld (_sdirty+2),hl
    xor a
    ld (_rr),a
    ld (_lasti),a
    call _st_saveorig
    ld a,(sf_kb)                ; capacity = kb * 1024
    add a,a
    add a,a
    ld h,a
    ld l,0
    ld (sf_cap),hl
    ld hl,(sf_kb)
    add hl,hl
    add hl,hl
    ld l,h
    ld h,0
    ld (sf_cap+2),hl
    ld a,2
    ld (_st_mem),a
    ld hl,1
    ret
_stf_exit:
    ld c,16
    call sf_bdos
    ld c,19
    jp sf_bdos
sf_name: defm "VIMISWP TMP"

; ================================================================ files
; BDOS function C with DE (the store window is closed first: BDOS and the window do not mix)
bd:
    push bc
    push de
    call _st_close
    pop de
    pop bc
    jp BDOS
bfcb:
    ld de,fs_fcb
    jr bd
setdma:
    ld c,26
    ld de,fs_dma
    jr bd
upc:
    cp 'a'
    ret c
    cp 'z'+1
    ret nc
    sub 32
    ret
; fs_fcb = the name at HL  ([d:]name[.ext])
mkf:
    push hl
    ld hl,fs_fcb
    ld de,fs_fcb+1
    ld (hl),0
    ld bc,35
    ldir
    ld hl,fs_fcb+1
    ld b,11
mf0:
    ld (hl),' '
    inc hl
    djnz mf0
    pop hl
    ld a,(hl)
    or a
    ret z
    inc hl
    ld a,(hl)
    dec hl
    cp ':'
    jr nz,mf1
    ld a,(hl)
    call upc
    sub 'A'-1
    ld (fs_fcb),a
    inc hl
    inc hl
mf1:
    ld de,fs_fcb+1
    ld b,8
mf2:
    ld a,(hl)
    or a
    ret z
    cp '.'
    jr z,mf4
    call upc
    ld (de),a
    inc hl
    inc de
    djnz mf2
mf3:
    ld a,(hl)
    or a
    ret z
    cp '.'
    jr z,mf4
    inc hl
    jr mf3
mf4:
    inc hl
    ld de,fs_fcb+9
    ld b,3
mf5:
    ld a,(hl)
    or a
    ret z
    call upc
    ld (de),a
    inc hl
    inc de
    djnz mf5
    ret

; int fs_stream(const char *name, int (*sink)(const u8 *buf, u8 n)) : feed the text of a file to sink (CR dropped);
; 0 = done, 1 = no such file, 2 = sink refused
_fs_stream:
    ld hl,2
    add hl,sp
    ld e,(hl)
    inc hl
    ld d,(hl)
    inc hl
    ld (fs_sink),de
    ld a,(hl)
    inc hl
    ld h,(hl)
    ld l,a
    call mkf
    xor a
    ld (fs_r),a
    call setdma
    ld c,15
    call bfcb
    inc a
    jr nz,st1
    ld hl,1
    ret
st1:
    ld hl,fs_dma                ; one record
    ld de,fs_dma+1
    ld (hl),1Ah
    ld bc,127
    ldir
    call setdma
    ld c,20
    call bfcb
    or a
    jr nz,st9
    ld hl,fs_dma
    ld de,fs_tmp
    ld bc,8000h                 ; B = 128 bytes to look at, C = bytes kept
st2:
    ld a,(hl)
    cp 1Ah
    jr z,st3
    or a
    jr z,st3
    cp 13
    jr z,st2a
    ld (de),a
    inc de
    inc c
st2a:
    inc hl
    djnz st2
st3:
    ld a,b
    ld (fs_i),a                 ; not 0 = the end of the text was in this record
    ld a,c
    or a
    jr z,st4
    ld hl,fs_tmp
    push hl
    ld l,c
    ld h,0
    push hl
    ld hl,(fs_sink)
    call jphl
    pop bc
    pop bc
    ld a,h
    or l
    jr nz,st4
    ld a,2
    ld (fs_r),a
    jr st9
st4:
    ld a,(fs_i)
    or a
    jr z,st1
st9:
    ld c,16
    call bfcb
    ld a,(fs_r)
    ld l,a
    ld h,0
    ret
jphl:
    jp (hl)

; the sink of fs_load: append to the store at ld_n, counting line breaks per block; 0 = it would not fit
ldsink:
    ld hl,2
    add hl,sp
    ld c,(hl)
    inc hl
    inc hl
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld b,0
    ld (ls_k),bc
    ld (ls_buf),de
    ld hl,(ld_n)
    add hl,bc
    ex de,hl
    ld hl,(ld_n+2)
    jr nc,ls0
    inc hl
ls0:
    push hl
    ex de,hl
    ld de,(ld_max)
    or a
    sbc hl,de
    pop hl
    ld de,(ld_max+2)
    sbc hl,de
    jr c,ls1
    ld hl,0
    ret
ls1:
    ld hl,(ld_n+2)
    push hl
    ld hl,(ld_n)
    push hl
    ld hl,(ls_buf)
    push hl
    ld hl,(ls_k)
    push hl
    call _tx_load_chunk
    pop bc
    pop bc
    pop bc
    pop bc
    ld hl,(ld_n+2)
    push hl
    ld hl,(ld_n)
    push hl
    ld hl,(ls_buf)
    push hl
    ld hl,0
    push hl
    ld hl,(ls_k)
    push hl
    call _st_write
    pop bc
    pop bc
    pop bc
    pop bc
    pop bc
    ld bc,(ls_k)
    ld hl,ld_n
    call add32
    ld hl,1
    ret

; pos_t fs_load(const char *name, pos_t max) : into the store from offset 0; bytes read, POS_NONE = no such file,
; POS_NONE - 1 = it does not fit in max bytes
_fs_load:
    ld hl,2
    add hl,sp
    ld de,ld_max
    ld bc,4
    ldir
    ld e,(hl)
    inc hl
    ld d,(hl)
    push de
    ld hl,0
    ld (ld_n),hl
    ld (ld_n+2),hl
    call _tx_load_begin
    ld hl,ldsink
    push hl
    call _fs_stream
    pop bc
    pop bc
    ld a,l
    dec a
    jr nz,fl1
    ld hl,0FFFFh
    ld d,h
    ld e,l
    ret
fl1:
    dec a
    jr nz,fl2
    ld hl,0FFFEh
    ld de,0FFFFh
    ret
fl2:
    ld hl,(ld_n)
    ld de,(ld_n+2)
    ret

; one byte into the output record; a full record is written.  NZ = write error
sput:
    ld c,a
    ld a,(fs_k)
    ld e,a
    ld d,0
    ld hl,fs_dma
    add hl,de
    ld (hl),c
    inc a
    ld (fs_k),a
    cp 128
    jr z,sp1
    xor a
    ret
sp1:
    xor a
    ld (fs_k),a
swrite:
    call setdma
    ld c,21
    call bfcb
    or a
    ret
; delete the file named at HL and create it again: Z if that failed
fs_new:
    push hl
    call mkf
    call setdma
    ld c,19
    call bfcb
    pop hl
    call mkf
    ld c,22
    call bfcb
    inc a
    ret

; int fs_save(const char *name, pos_t len) : the text [0, len) to the file (LF -> CRLF, ^Z padding); 0 = ok
_fs_save:
    ld hl,2
    add hl,sp
    ld de,sa_len
    ld bc,4
    ldir
    ld a,(hl)
    inc hl
    ld h,(hl)
    ld l,a
    call fs_new
    jp z,sa_err
    xor a
    ld (fs_k),a
    ld h,a
    ld l,a
    ld (sa_i),hl
    ld (sa_i+2),hl
sa1:
    ld hl,(sa_len)              ; the next 64 bytes at most
    ld de,(sa_i)
    or a
    sbc hl,de
    ex de,hl
    ld hl,(sa_len+2)
    ld bc,(sa_i+2)
    sbc hl,bc
    ld a,h
    or l
    or d
    jr nz,sa1a
    ld a,e
    or a
    jr z,sa5
    cp 65
    jr c,sa1b
sa1a:
    ld a,64
sa1b:
    ld (sa_got),a
    ld hl,fs_tmp
    push hl
    ld hl,(sa_i+2)
    push hl
    ld hl,(sa_i)
    push hl
    ld hl,0
    push hl
    ld l,a
    push hl
    call _tx_read
    pop bc
    pop bc
    pop bc
    pop bc
    pop bc
    xor a
    ld (sa_j),a
sa2:
    ld a,(sa_j)
    ld hl,sa_got
    cp (hl)
    jr nc,sa4
    ld e,a
    ld d,0
    ld hl,fs_tmp
    add hl,de
    ld a,(hl)
    cp 10
    jr nz,sa3
    ld a,13
    call sput
    jr nz,sa_err
    ld a,10
sa3:
    call sput
    jr nz,sa_err
    ld hl,sa_j
    inc (hl)
    jr sa2
sa4:
    ld a,(sa_got)
    ld c,a
    ld b,0
    ld hl,sa_i
    call add32
    jr sa1
sa5:
    ld a,(fs_k)
    or a
    jr z,sa7
sa6:
    ld a,1Ah                    ; pad the last record
    call sput
    jr nz,sa_err
    ld a,(fs_k)
    or a
    jr nz,sa6
sa7:
    ld c,16
    call bfcb
    inc a
    jr z,sa_err
    ld hl,0
    ret
sa_err:
    ld hl,0FFFFh
    ret

; void fs_erase(const char *name)
_fs_erase:
    ld hl,2
    add hl,sp
    ld a,(hl)
    inc hl
    ld h,(hl)
    ld l,a
    call mkf
    call setdma
    ld c,19
    jp bfcb

; the string at HL into the output file
bstr:
    ld a,(hl)
    or a
    ret z
    push hl
    call sput
    pop hl
    inc hl
    jr bstr
; int fs_bat(const char *cmd, const char *file, u16 line) : VIMICMD.BAT = "cmd / pause / V +line file" (the fallback
; of :!cmd on an OS without E5h; V.BAT runs it after the editor has quit); 0 = ok
_fs_bat:
    ld hl,2
    add hl,sp
    ld de,bt_line
    ld bc,6
    ldir
    ld hl,s_bat
    call fs_new
    jr z,sa_err
    xor a
    ld (fs_k),a
    ld hl,(bt_cmd)
    call bstr
    ld a,(fs_k)                 ; the batch reader ends on a line shorter than 4 characters
bt1:
    cp 4
    jr nc,bt2
    ld a,' '
    call sput
    ld a,(fs_k)
    jr bt1
bt2:
    ld hl,s_mid
    call bstr
    ld hl,dvtab                 ; the line number, without leading zeros
    ld (bt_p),hl
    xor a
    ld (bt_st),a
    ld a,5
    ld (bt_i),a
bt3:
    ld hl,(bt_p)
    ld c,(hl)
    inc hl
    ld b,(hl)
    inc hl
    ld (bt_p),hl
    ld hl,(bt_line)
    ld a,'0'-1
bt4:
    inc a
    or a
    sbc hl,bc
    jr nc,bt4
    add hl,bc
    ld (bt_line),hl
    cp '0'
    jr nz,bt5
    ld c,a
    ld a,(bt_i)
    dec a
    jr z,bt5a
    ld a,(bt_st)
    or a
    jr z,bt6
bt5a:
    ld a,c
bt5:
    ld c,a
    ld a,1
    ld (bt_st),a
    ld a,c
    call sput
bt6:
    ld hl,bt_i
    dec (hl)
    jr nz,bt3
    ld a,' '
    call sput
    ld hl,(bt_file)
    call bstr
    ld hl,s_crlf
    call bstr
bt7:
    ld a,(fs_k)
    or a
    jr z,bt8
    ld a,1Ah
    call sput
    jr bt7
bt8:
    ld c,16
    call bfcb
    ld hl,0
    ret
dvtab:  defw 10000, 1000, 100, 10, 1
s_bat:  defm "VIMICMD.BAT"
    defb 0
s_mid:  defb 13, 10
    defm "pause"
    defb 13, 10
    defm "V +"
    defb 0
s_crlf: defb 13, 10, 0
s_pak:  defb 13, 10
    defm "Press any key"
    defb 0

; ================================================================ video / keyboard glue
; the text CRT-C start address (cells, 0..7FFh) = HL
set_start:
    ld a,h
    and 7
    ld h,a
    ld (_hw_start),hl
    jp _crtc_start
; void hal_scroll(int n) : scroll the picture n rows by moving the start address
_hal_scroll:
    ld hl,2
    add hl,sp
    ld a,(hl)
    inc hl
    ld h,(hl)
    ld l,a
    call mul80
    ld de,(_hw_start)
    add hl,de
    jr set_start
mul80:
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    ld d,h
    ld e,l
    add hl,hl
    add hl,hl
    add hl,de
    ret
; void hal_putrow(u8 y, const u8 *chars, const u8 *attrs)
_hal_putrow:
    ld hl,2
    add hl,sp
    ld e,(hl)
    inc hl
    ld d,(hl)
    inc hl
    ld (_rw_attrs),de
    ld e,(hl)
    inc hl
    ld d,(hl)
    inc hl
    ld (_rw_chars),de
    ld l,(hl)
    ld h,0
    call mul80
    ld de,(_hw_start)
    add hl,de
    ld a,h
    and 7
    or 0E0h
    ld h,a
    ld (_rw_adr),hl
    jp _vram_row
_hal_init:
    call _kbd_install
    jp _pal_on
_hal_exit:
    call _kbd_remove
    call _pal_off
    ld hl,(_hw_start)
    ld a,h
    or l
    ret z
    call _vram_clear            ; blank everything first: the rotated picture must never become visible
    ld hl,0
    jr set_start
; int hal_getkey(void) : wait for a key
_hal_getkey:
    call _kbd_get
    ld a,h
    or l
    ret nz
    halt
    jr _hal_getkey
; void hal_clear(void) : clear the screen through the OS console
_hal_clear:
    call _st_close
    ld e,0Ch
conout:
    ld c,2
    jp BDOS

; int fs_exec(const char *cmd, u8 wait) : run a command with the LSX E5h call; its result, or 0FEh if the OS cannot
_fs_exec:
    call _exec_ok
    ld a,l
    or a
    jr nz,fx1
    ld hl,0FEh
    ret
fx1:
    call _hal_exit
    call _hal_clear
    ld hl,4
    add hl,sp
    ld a,(hl)
    inc hl
    ld h,(hl)
    ld l,a
    push hl
    call _exec_call
    pop bc
    ld a,l
    ld (fx_r),a
    cp 0F0h
    jr nc,fx4
    or a
    jr nz,fx2
    ld hl,2
    add hl,sp
    ld a,(hl)
    or a
    jr z,fx4
fx2:
    ld hl,s_pak
fx3:
    ld a,(hl)
    or a
    jr z,fx3a
    push hl
    ld e,a
    call conout
    pop hl
    inc hl
    jr fx3
fx3a:
    ld c,1
    call BDOS
fx4:
    call _hal_init
    call _hal_clear
    ld a,(fx_r)
    ld l,a
    ld h,0
    ret

; ================================================================ int main(int argc, char **argv)
_main:
    ld hl,2
    add hl,sp
    ld c,(hl)                   ; the crt0 pushes argv, then argc
    inc hl
    inc hl
    ld e,(hl)
    inc hl
    ld d,(hl)                   ; DE = argv, C = argc
    ld hl,0
    ld (mn_file),hl
    ld (mn_line),hl
    ld a,c
    ld (mn_n),a
mn1:
    ld hl,mn_n                  ; the arguments after the program name
    dec (hl)
    jr z,mn9
    jp m,mn9
    inc de
    inc de
    ld a,(de)
    ld l,a
    inc de
    ld a,(de)
    dec de
    ld h,a                      ; HL = argv[i]
    ld (mn_arg),hl
    ld a,(hl)
    cp '+'
    jr nz,mn2
    inc hl                      ; +N: start on line N
    call atoi
    ld (mn_line),bc
    jr mn1
mn2:
    cp '-'
    jr nz,mn5
    inc hl
    ld a,(hl)
    or 20h
    cp 'n'
    jr nz,mn3
    xor a                       ; -n: keep the OS palette
    ld (_pal_enable),a
    jr mn1
mn3:
    cp 's'
    jr nz,mn4
    inc hl
    ld a,(hl)
    or a
    jr z,mn4
    push de                     ; -sD[KB]: swap file on drive D
    ld e,a
    ld d,0
    push de
    inc hl
    call atoi
    push bc
    call _st_select
    pop bc
    pop bc
    pop de
    jr mn1
mn4:
    ld hl,(mn_arg)              ; anything else is the file name
mn5:
    ld (mn_file),hl
    jr mn1
mn9:
    call _st_init
    call _hal_init
    call _hal_clear
    call _ed_init
    ld hl,s_bat                 ; a finished :!cmd leaves this behind
    push hl
    call _fs_erase
    pop bc
    ld hl,(mn_file)
    ld a,h
    or l
    jr z,mn10
    push hl
    call _ed_load
    pop bc
mn10:
    ld hl,(mn_line)
    ld a,h
    or l
    jr z,mn11
    push hl
    call _ed_goto
    pop bc
mn11:
    call _ed_quit
    ld a,l
    or a
    jr nz,mn12
    call _ed_render
    call _hal_getkey
    ld h,0
    push hl
    call _ed_key
    pop bc
    jr mn11
mn12:
    call _hal_exit
    call _st_exit
    call _hal_clear
    ld hl,0
    ret
; BC = the decimal number at HL (HL moves past it).  Keeps DE.
atoi:
    ld bc,0
at1:
    ld a,(hl)
    sub '0'
    cp 10
    ret nc
    push hl
    ld h,b
    ld l,c
    add hl,hl
    add hl,hl
    add hl,bc
    add hl,hl
    ld c,a
    ld b,0
    add hl,bc
    ld b,h
    ld c,l
    pop hl
    inc hl
    jr at1

    SECTION bss_user
_hw_start: defs 2
_rw_adr: defs 2
_rw_chars: defs 2
_rw_attrs: defs 2
st_drv: defb 0
st_one: defb 0
st_kb:  defs 2
st_bounce: defs 128
mv_n:   defs 4                  ; (mv_n, mv_s, mv_d: the stack image of st_move)
mv_s:   defs 4
mv_d:   defs 4
mv_kk:  defs 2
fb_c:   defs 2                  ; (fb_c, fb_e, fb_o: the stack image of st_findb / st_rfindb / st_countb)
fb_e:   defs 4
fb_o:   defs 4
sf_d:   defb 0
sf_kb:  defs 2
sf_r:   defs 2
sf_cap: defs 4
fs_fcb: defs 36
fs_dma: defs 128
fs_tmp: defs 128
fs_sink: defs 2
fs_r:   defb 0
fs_i:   defb 0
fs_k:   defb 0
ld_n:   defs 4
ld_max: defs 4
ls_k:   defs 2
ls_buf: defs 2
sa_len: defs 4
sa_i:   defs 4
sa_got: defb 0
sa_j:   defb 0
bt_line: defs 2                 ; (bt_line, bt_file, bt_cmd: the stack image of fs_bat)
bt_file: defs 2
bt_cmd: defs 2
bt_p:   defs 2
bt_i:   defb 0
bt_st:  defb 0
fx_r:   defb 0
mn_file: defs 2
mn_line: defs 2
mn_n:   defb 0
mn_arg: defs 2
