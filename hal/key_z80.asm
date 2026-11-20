; key_z80.asm - the key entry point (the asm twin of busy / key1 / ed_key in core/editor.c; -DM_ASM)
;   void ed_key(u8 k) : one key from the keyboard, then whatever it queued (the keys of a dot-repeat, then those of a macro)
    SECTION code_user
    PUBLIC _ed_key
    EXTERN pusha, _clampcur, _setmsg, _regstore, _normal_key, _insert_key, _cmd_key, _visual_key
    EXTERN _mode, _count, _pend, _pq, _pf, _vp, _reg, _msg, _mrc, _inmac, _replay, _ri, _mlen, _mb, _mc, _mi
    EXTERN _rec, _lastrec, _reclen, _lastlen, _recbad, _chg, _uwarn, _m_noundo, _ud, _u_n, _u_grp, _ugrp
    defc MACB = 80              ; MB    (core/ed_reg.c)
    defc RECSZ = 32             ; RECSZ (core/editor.c)

; NZ if a command is half typed (operator, count, "x register, f/t target)
busy:
    ld hl,(_count)
    ld a,h
    or l
    ld hl,_pend
    or (hl)
    ld hl,_pq
    or (hl)
    ld hl,_pf
    or (hl)
    ret

_ed_key:
    ld hl,2
    add hl,sp
    ld a,(hl)
ek0:
    call key1
    ld a,(_replay)
    or a
    jr z,ek2
    ld a,(_ri)                  ; dot-repeat: its keys come first, so that a . inside a macro works
    ld hl,_lastlen
    cp (hl)
    jr nc,ek1
    ld e,a
    ld d,0
    inc a
    ld (_ri),a
    ld hl,_lastrec
    add hl,de
    ld a,(hl)
    jr ek0
ek1:
    xor a
    ld (_replay),a
    ld (_chg),a
ek2:
    ld a,(_inmac)
    or a
    jr z,ek4
    ld a,(_mi)
    ld hl,_mlen
    cp (hl)
    jr nz,ek3
    xor a
    ld (_mi),a
    ld hl,(_mc)
    dec hl
    ld (_mc),hl
    ld a,h
    or l
    jr nz,ek3
    ld (_inmac),a
    jr ek4
ek3:
    ld a,(_mi)
    ld e,a
    ld d,0
    inc a
    ld (_mi),a
    ld hl,_mb
    add hl,de
    ld a,(hl)
    jr ek0
ek4:
    ld a,(_uwarn)
    or a
    ret z
    xor a
    ld (_uwarn),a
    ld hl,_m_noundo
    push hl
    call _setmsg
    pop bc
    ret

key1:
    ld (ky_k),a
    xor a
    ld (_msg),a
    ld a,(_mrc)                 ; recording a macro (the keys a . replays are not typed: the . itself is recorded)
    or a
    jr z,k2
    ld a,(_inmac)
    ld hl,_replay
    or (hl)
    jr nz,k2
    ld a,(ky_k)
    cp 'q'
    jr nz,k1
    ld a,(_mode)
    or a
    jr nz,k1
    call busy
    jr nz,k1
    ld a,(_mrc)                 ; q ends the recording
    ld (_reg),a
    ld hl,_mb
    push hl
    ld a,(_mlen)
    call pusha
    xor a
    call pusha
    call _regstore
    pop bc
    pop bc
    pop bc
    xor a
    ld (_reg),a
    ld (_mrc),a
    ret
k1:
    ld a,(_mlen)
    cp MACB
    jr nc,k2
    ld hl,_mb
    call putk
    ld (_mlen),a
k2:
    ld b,0                      ; B = idle: a new command starts with this key
    ld a,(_mode)
    or a
    jr nz,k3
    call busy
    jr nz,k3
    ld a,(_reg)
    or a
    jr nz,k3
    inc b
k3:
    ld a,b
    ld (ky_idle),a
    ld a,(_replay)
    or a
    jr nz,k5
    or b
    jr z,k4
    xor a
    ld (_reclen),a
    ld (_recbad),a
    ld (_chg),a
k4:
    ld a,(_reclen)              ; remember the keys of the command for .
    cp RECSZ
    jr nc,k4a
    ld hl,_rec
    call putk
    ld (_reclen),a
    jr k5
k4a:
    ld a,1
    ld (_recbad),a
k5:
    ld a,(ky_idle)
    or a
    jr z,k7
    ld hl,(_ud)                 ; a new undo group id only if the current one was used (or dropped)
    ld a,h
    or l
    jr nz,k6
    ld a,(_u_n)
    or a
    jr z,k6a
    ld e,a
    ld d,0
    ld hl,_u_grp-1
    add hl,de
    ld a,(_ugrp)
    cp (hl)
    jr nz,k6a
k6:
    ld hl,_ugrp
    inc (hl)
k6a:
    ld hl,0
    ld (_ud),hl
    ld (_ud+2),hl
k7:
    ld a,(_pq)                  ; "x : the register for the next command
    or a
    jr nz,k8
    ld a,(ky_k)
    cp '"'
    jr nz,k9
    ld a,(_pf)
    ld hl,_pend
    or (hl)
    ld hl,_vp
    or (hl)
    jr nz,k9
    ld a,(_mode)
    or a
    jr z,k7a
    cp 3
    jr nz,k9
k7a:
    ld a,1
    ld (_pq),a
    ret
k8:
    ld a,(ky_k)
    ld c,a
    or 20h
    cp 'a'
    jr c,k8a
    cp 'z'+1
    jr nc,k8a
    ld a,c
    jr k8b
k8a:
    xor a
k8b:
    ld (_reg),a
    xor a
    ld (_pq),a
    ret
k9:
    ld a,(ky_k)
    ld l,a
    ld h,0
    ld a,(_mode)
    or a
    jr nz,k9a
    call _normal_key
    jr k10
k9a:
    dec a
    jr nz,k9b
    call _insert_key
    jr k10
k9b:
    dec a
    jr nz,k9c
    call _cmd_key
    jr k10
k9c:
    call _visual_key
k10:
    ld a,(_mode)                ; outside insert and command-line mode the cursor stays on a character
    dec a
    cp 2
    call nc,_clampcur
    call busy
    jr nz,k12
    ld a,(_mode)
    dec a
    jr z,k12
    xor a
    ld (_reg),a
k12:
    ld a,(_replay)              ; a finished command that changed the text becomes the one . repeats
    ld hl,_mode
    or (hl)
    ld hl,_recbad
    or (hl)
    ret nz
    call busy
    ret nz
    ld a,(_chg)
    or a
    ret z
    ld a,(_reclen)
    ld (_lastlen),a
    or a
    jr z,k13
    ld c,a
    ld b,0
    ld hl,_rec
    ld de,_lastrec
    ldir
k13:
    xor a
    ld (_chg),a
    ret
; (HL)[A] = key; A = A + 1
putk:
    ld e,a
    ld d,0
    add hl,de
    ld e,a
    ld a,(ky_k)
    ld (hl),a
    ld a,e
    inc a
    ret

    SECTION bss_user
ky_k:    defb 0
ky_idle: defb 0
