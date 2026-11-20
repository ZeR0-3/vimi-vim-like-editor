; undo_z80.asm - logged text edits and undo / redo (the asm twin of most of core/ed_undo.c and of cmd_undo; -DM_ASM)
;   tins tinsn tdel mins touched keepinvariant : the primitives every edit goes through
;   ulog_add : one entry into log L (0 = undo, 1 = redo), dropping the oldest groups when the log is full
;   cmd_undo : u and Ctrl-R
; The entry tables (u_typ u_pos u_len u_off u_grp [2][24], u_n u_dn [2]) are in core/ed_undo.c; ulog_put / ulog_merge /
; ulog_shift are in ulog_z80.asm.  Undo data of log L sits in the aux area at 1024 + 512 * L.
    SECTION code_user
    PUBLIC _tins, _tinsn, _tdel, _mins, _touched, _keepinvariant, _ulog_add, _cmd_undo
    EXTERN ldcur, stcur, dec32, cmpm, addm, pusha
    EXTERN _lstart, _clampcur, _setwant, _setmsg
    EXTERN _tx_len, _tx_ins, _tx_del, _tx_read, _tx_aux_put, _tx_aux_get, _tx_aux_move, _madj
    EXTERN _ulog_put, _ulog_merge, _ulog_shift
    EXTERN _u_typ, _u_pos, _u_len, _u_off, _u_grp, _u_n, _u_dn, _ud, _uwarn, _ugrp
    EXTERN _cur, _mode, _modified, _chg, _lc_pos, _lc_line, _ibuf, _m_full
    defc UE = 24
    defc UD = 512
    defc ISZ = 64

; ---- unlogged insert / delete on (mi_p, mi_n, mi_d), keeping the marks right
; u8 mins(pos_t p, const u8 *d, pos_t n)
_mins:
    ld hl,2
    add hl,sp
    ld de,mi_n
    ld bc,10
    ldir
mins_m:                         ; -> Z (HL = 0) if there is no room
    ld hl,(mi_p+2)
    push hl
    ld hl,(mi_p)
    push hl
    ld hl,(mi_d)
    push hl
    ld hl,(mi_n+2)
    push hl
    ld hl,(mi_n)
    push hl
    call _tx_ins
    pop bc
    pop bc
    pop bc
    pop bc
    pop bc
    ld a,l
    or a
    ret z
    ld a,1
madj_m:
    ld c,a
    ld hl,(mi_p+2)
    push hl
    ld hl,(mi_p)
    push hl
    ld hl,(mi_n+2)
    push hl
    ld hl,(mi_n)
    push hl
    ld a,c
    call pusha
    call _madj
    pop bc
    pop bc
    pop bc
    pop bc
    pop bc
    ld hl,1
    ld a,l
    or a
    ret
mdel_m:
    ld hl,(mi_p+2)
    push hl
    ld hl,(mi_p)
    push hl
    ld hl,(mi_n+2)
    push hl
    ld hl,(mi_n)
    push hl
    call _tx_del
    pop bc
    pop bc
    pop bc
    pop bc
    xor a
    jr madj_m

; void touched(pos_t p) : bookkeeping after a logged edit at p: line cache, modified flag, redo is void
_touched:
    ld hl,2
    add hl,sp
    ld de,mi_p
    ld bc,4
    ldir
touched_m:
    ld hl,mi_p
    ld de,_lc_pos
    call cmpm
    call c,lc_reset
    ld a,1
    ld (_modified),a
    ld (_chg),a
    xor a
    ld (_u_n+1),a
    ld h,a
    ld l,a
    ld (_u_dn+2),hl
    ret
lc_reset:
    ld hl,0
    ld (_lc_pos),hl
    ld (_lc_pos+2),hl
    ld (_lc_line+2),hl
    inc hl
    ld (_lc_line),hl
    ret
full_ret:
    ld hl,_m_full
    push hl
    call _setmsg
    pop bc
    ld hl,0
    ret

; A = type (0 INS, 1 DEL), HL = data in memory or 0, DE = aux offset of the data or 0FFFFh (= take it from the text):
; add (mi_p, mi_n) to the undo log in the current group
ula_std:
    ld (ua_typ),a
    ld (ua_src),hl
    ld (ua_aoff),de
    xor a
    ld (ua_L),a
    ld a,(_ugrp)
    ld (ua_grp),a
    ld hl,mi_n
    ld de,ua_len
    ld bc,4
    ldir
    ld hl,mi_p
    ld bc,4
    ldir
    jp ula

; u8 tins(pos_t p, u8 c) : insert one character (a run of typed characters becomes one undo entry)
_tins:
    ld hl,2
    add hl,sp
    ld a,(hl)
    ld (ti_c),a
    inc hl
    inc hl
    ld de,mi_p
    ld bc,4
    ldir
    ld hl,1
    ld (mi_n),hl
    dec hl
    ld (mi_n+2),hl
    ld hl,ti_c
    ld (mi_d),hl
    call mins_m
    jr z,full_ret
    call touched_m
    ld hl,(mi_p+2)
    push hl
    ld hl,(mi_p)
    push hl
    call _ulog_merge
    pop bc
    pop bc
    ld a,h
    or l
    jr z,ti2
    ld de,1024
    add hl,de
    push hl
    ld hl,ti_c
    push hl
    ld hl,1
    push hl
    call _tx_aux_put
    pop bc
    pop bc
    pop bc
    ld hl,1
    ret
ti2:
    ld hl,ti_c
    ld d,a
    ld e,a
    call ula_std
    ld hl,1
    ret

; u8 tinsn(pos_t p, const u8 *d, pos_t n) : insert n bytes
_tinsn:
    ld hl,2
    add hl,sp
    ld de,mi_n
    ld bc,10
    ldir
    call mins_m
    jp z,full_ret
    call touched_m
    xor a
    ld hl,(mi_d)
    ld d,a
    ld e,a
    call ula_std
    ld hl,1
    ret

; void tdel(pos_t p, pos_t n) : delete n bytes (the text is saved in the log first)
_tdel:
    ld hl,2
    add hl,sp
    ld de,mi_n
    ld bc,4
    ldir
    ld de,mi_p
    ld bc,4
    ldir
    ld a,1
    ld hl,0
    ld de,0FFFFh
    call ula_std
    call mdel_m
    jp touched_m

; void keepinvariant(void) : the text always ends with a line break and the cursor is inside it
_keepinvariant:
    call _tx_len
    ld a,h
    or l
    or d
    or e
    jr nz,ki1
    ld h,a
    ld l,a
    push hl
    push hl
    ld l,10
    push hl
    call _tins
    pop bc
    pop bc
    pop bc
ki1:
    call _tx_len
    ld (ua_t),hl
    ld (ua_t+2),de
    ld hl,_cur
    ld de,ua_t
    call cmpm
    ret c
    ld hl,(ua_t)
    ld de,(ua_t+2)
    call dec32
    call _lstart
    jp stcur

; ---- the log
; pointers into the tables of log ua_L
un_ptr:
    ld hl,_u_n
    ld a,(ua_L)
    jr ptr_a
udn_ptr:
    ld hl,_u_dn
    jr ptr_2
ud_ptr:
    ld hl,_ud
ptr_2:
    ld a,(ua_L)
    add a,a
ptr_a:
    ld e,a
    ld d,0
    add hl,de
    ret
grp_ptr:
    ld hl,_u_grp
    ld a,(ua_L)
    or a
    ret z
    ld de,UE
    add hl,de
    ret
; HL = aux offset of the data of log A
uoff:
    add a,a
    add a,4
    ld h,a
    ld l,0
    ret
; HL = min(HL, ISZ)
chunk:
    ld a,h
    or a
    jr nz,ch1
    ld a,l
    cp ISZ+1
    ret c
ch1:
    ld hl,ISZ
    ret

; void ulog_add(u8 L, u8 typ, pos_t pos, pos_t len32, const u8 *src, u16 aoff, u8 grp)
_ulog_add:
    ld hl,2
    add hl,sp
    ld de,ua_grp
    ld bc,18
    ldir
ula:
    call ud_ptr                 ; this group was already dropped as a whole?
    ld a,(ua_grp)
    cp (hl)
    jr nz,ula1
    inc hl
    ld a,(hl)
    dec a
    ret z
ula1:
    ld hl,(ua_len+2)            ; make room: bigger than the whole log?
    ld a,h
    or l
    jr nz,ula_fg
    ld hl,(ua_len)
    ld de,UD+1
    or a
    sbc hl,de
    jr nc,ula_fg
    call un_ptr
    ld a,(hl)
    cp UE
    jr nc,ula2                  ; no free entry
    call udn_ptr
    ld a,(hl)
    inc hl
    ld h,(hl)
    ld l,a
    ld de,(ua_len)
    add hl,de
    ld de,UD+1
    or a
    sbc hl,de
    jr c,ula_put                ; the data fits
ula2:
    call un_ptr
    ld a,(hl)
    or a
    jr z,ula_fg
    ld c,a
    call grp_ptr
    ld a,(ua_grp)
    cp (hl)
    jr nz,ula3
    ld b,0
    dec c
    add hl,bc
    cp (hl)
    jr z,ula_fg                 ; the whole log is this very group
ula3:
    call drop
    jr ula1
ula_fg:                         ; it does not fit: forget the group entirely (all or nothing)
    call un_ptr
    ld (hl),0
    call udn_ptr
    xor a
    ld (hl),a
    inc hl
    ld (hl),a
    call ud_ptr
    ld a,(ua_grp)
    ld (hl),a
    inc hl
    ld (hl),1
    ld a,(ua_L)
    or a
    ret nz
    inc a
    ld (_uwarn),a
    ret
ula_put:
    ld a,(ua_L)
    call pusha
    ld a,(ua_typ)
    call pusha
    ld hl,(ua_pos+2)
    push hl
    ld hl,(ua_pos)
    push hl
    ld hl,(ua_len)
    push hl
    ld a,(ua_grp)
    call pusha
    call _ulog_put
    ld hl,12
    add hl,sp
    ld sp,hl
    call udn_ptr                ; where the data goes
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld a,(ua_L)
    call uoff
    add hl,de
    ld (ua_d),hl
    ld de,(ua_src)
    ld a,d
    or e
    jr z,up1
    push hl                     ; from memory
    push de
    ld hl,(ua_len)
    push hl
    call _tx_aux_put
    jr up2
up1:
    ld de,(ua_aoff)
    ld a,d
    and e
    inc a
    jr z,up3
    push hl                     ; from another place in the aux area
    push de
    ld hl,(ua_len)
    push hl
    call _tx_aux_move
up2:
    pop bc
    pop bc
    pop bc
    jr up9
up3:
    ld hl,0                     ; from the text, through the scratch buffer
    ld (ua_i),hl
up4:
    ld hl,(ua_len)
    ld de,(ua_i)
    or a
    sbc hl,de
    jr z,up9
    call chunk
    ld (ua_m),hl
    ld hl,_ibuf
    push hl
    ld hl,(ua_i)
    ld de,ua_pos
    call addm
    push de
    push hl
    ld hl,0
    push hl
    ld hl,(ua_m)
    push hl
    call _tx_read
    pop bc
    pop bc
    pop bc
    pop bc
    pop bc
    ld hl,(ua_d)
    ld de,(ua_i)
    add hl,de
    push hl
    ld hl,_ibuf
    push hl
    ld hl,(ua_m)
    push hl
    call _tx_aux_put
    pop bc
    pop bc
    pop bc
    ld hl,(ua_i)
    ld de,(ua_m)
    add hl,de
    ld (ua_i),hl
    jr up4
up9:
    call udn_ptr
    ld e,(hl)
    inc hl
    ld d,(hl)
    push hl
    ld hl,(ua_len)
    add hl,de
    ex de,hl
    pop hl
    ld (hl),d
    dec hl
    ld (hl),e
    call un_ptr
    inc (hl)
    ret

; drop the oldest group of log ua_L (it has at least one entry)
drop:
    call un_ptr
    ld a,(hl)
    ld (dr_n),a
    call grp_ptr
    ld c,(hl)
    ld b,1
dr1:
    inc hl
    ld a,(dr_n)
    dec a
    cp b
    jr c,dr_all
    ld a,(hl)
    cp c
    jr nz,dr2
    inc b
    jr dr1
dr_all:
    call un_ptr
    ld (hl),0
    call udn_ptr
    xor a
    ld (hl),a
    inc hl
    ld (hl),a
    ret
dr2:
    ld a,b
    ld (dr_k),a
    ld hl,_u_off                ; cut = u_off[L][k]
    ld a,(ua_L)
    or a
    jr z,dr3
    ld de,UE*2
    add hl,de
dr3:
    ld e,b
    ld d,0
    add hl,de
    add hl,de
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld (dr_cut),de
    ld a,(ua_L)
    call uoff
    push hl
    add hl,de
    push hl
    call udn_ptr
    ld a,(hl)
    inc hl
    ld h,(hl)
    ld l,a
    ld de,(dr_cut)
    or a
    sbc hl,de
    ld (ua_m),hl
    push hl
    call _tx_aux_move
    pop bc
    pop bc
    pop bc
    call udn_ptr
    ld de,(ua_m)
    ld (hl),e
    inc hl
    ld (hl),d
    ld a,(ua_L)
    call pusha
    ld a,(dr_k)
    call pusha
    ld hl,(dr_cut)
    push hl
    call _ulog_shift
    pop bc
    pop bc
    pop bc
    call un_ptr
    ld a,(dr_k)
    ld c,a
    ld a,(hl)
    sub c
    ld (hl),a
    ret

; ---- u / Ctrl-R
; HL = base of a [2][24] table, A = element size (1, 2, 4): HL -> element cu_t of log cu_from
arr:
    push hl
    ld b,a
    ld hl,0
    ld a,(cu_from)
    or a
    jr z,ar1
    ld l,UE
ar1:
    ld a,(cu_t)
    ld e,a
    ld d,0
    add hl,de
    ld a,b
ar2:
    rra
    jr c,ar3
    add hl,hl
    jr ar2
ar3:
    pop de
    add hl,de
    ret
; HL -> u_n[cu_from], A = its value
cu_n:
    ld a,(cu_from)
    ld e,a
    ld d,0
    ld hl,_u_n
    add hl,de
    ld a,(hl)
    ret

; void cmd_undo(u8 redo) fastcall
_cmd_undo:
    ld a,l
    or a
    jr z,cu0
    ld a,1
cu0:
    ld (cu_from),a
    xor 1
    ld (ua_L),a                 ; the reverse operations are queued on the other log
    call cu_n
    or a
    jr nz,cu1
    ld hl,s_old
    ld a,(cu_from)
    or a
    jr z,cu0a
    ld hl,s_new
cu0a:
    push hl
    call _setmsg
    pop bc
    ret
cu1:
    dec a
    ld (cu_t),a
    ld hl,_u_grp
    ld a,1
    call arr
    ld a,(hl)
    ld (ua_grp),a
    call ldcur
    ld (cu_first),hl
    ld (cu_first+2),de
cu2:
    call cu_n                   ; every entry of the group, newest first
    or a
    jp z,cu9
    dec a
    ld (cu_t),a
    ld hl,_u_grp
    ld a,1
    call arr
    ld a,(ua_grp)
    cp (hl)
    jp nz,cu9
    ld hl,_u_pos
    ld a,4
    call arr
    ld de,ua_pos
    ld bc,4
    ldir
    ld hl,_u_len
    ld a,2
    call arr
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld (ua_len),de
    ld hl,0
    ld (ua_len+2),hl
    ld (ua_src),hl
    ld hl,_u_off
    ld a,2
    call arr
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld (cu_off),de
    ld a,(cu_from)
    call uoff
    add hl,de
    ld (ua_aoff),hl
    ld hl,_u_typ
    ld a,1
    call arr
    ld a,(hl)
    ld (ua_typ),a
    ld hl,ua_pos                ; (ula does not change ua_pos / ua_len / ua_aoff / ua_typ)
    ld de,cu_first
    ld bc,4
    ldir
    call ula
    ld hl,ua_pos
    ld de,mi_p
    ld bc,4
    ldir
    ld hl,(ua_len)
    ld (mi_n),hl
    ld hl,0
    ld (mi_n+2),hl
    ld a,(ua_typ)               ; undo: INS -> delete, DEL -> insert; redo: the opposite
    sub 1
    sbc a,a
    and 1
    ld hl,cu_from
    xor (hl)
    jr z,cu3
    call mdel_m
    jr cu5
cu3:
    ld hl,0                     ; insert ua_len bytes from the aux area at ua_aoff
    ld (ua_i),hl
cu4:
    ld hl,(ua_len)
    ld de,(ua_i)
    or a
    sbc hl,de
    jr z,cu5
    call chunk
    ld (ua_m),hl
    ld (mi_n),hl
    ld hl,_ibuf
    ld (mi_d),hl
    push hl
    ld hl,(ua_aoff)
    ld de,(ua_i)
    add hl,de
    push hl
    ld hl,(ua_m)
    push hl
    call _tx_aux_get
    pop bc
    pop bc
    pop bc
    ld hl,(ua_i)
    ld de,ua_pos
    call addm
    ld (mi_p),hl
    ld (mi_p+2),de
    call mins_m
    jr nz,cu4a
    call full_ret
    jr cu5
cu4a:
    ld hl,(ua_i)
    ld de,(ua_m)
    add hl,de
    ld (ua_i),hl
    jr cu4
cu5:
    ld a,1
    ld (_modified),a
    call lc_reset
    call cu_n                   ; pop the entry
    ld a,(cu_t)
    ld (hl),a
    ld hl,_u_dn
    ld a,(cu_from)
    add a,a
    ld e,a
    ld d,0
    add hl,de
    ld de,(cu_off)
    ld (hl),e
    inc hl
    ld (hl),d
    jp cu2
cu9:
    call _keepinvariant
    xor a
    ld (_mode),a
    ld hl,(cu_first)
    ld de,(cu_first+2)
    call stcur
    call _clampcur
    jp _setwant

s_old:  defm "already at oldest change"
    defb 0
s_new:  defm "already at newest change"
    defb 0

    SECTION bss_user
mi_n:   defs 4                  ; (mi_n, mi_d, mi_p: the stack image of mins / tinsn)
mi_d:   defs 2
mi_p:   defs 4
ua_grp: defs 2                  ; (ua_grp .. ua_L: the stack image of ulog_add)
ua_aoff: defs 2
ua_src: defs 2
ua_len: defs 4
ua_pos: defs 4
ua_typ: defs 2
ua_L:   defs 2
ua_d:   defs 2
ua_i:   defs 2
ua_m:   defs 2
ua_t:   defs 4
ti_c:   defb 0
dr_n:   defb 0
dr_k:   defb 0
dr_cut: defs 2
cu_from: defb 0
cu_t:   defb 0
cu_off: defs 2
cu_first: defs 4
