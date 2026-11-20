; kbd_isr.asm - MZ-2500 keyboard: VBLANK-interrupt matrix scan -> 16-byte ring buffer (no LSX/IOCS needed).
; The IM1 vector (0038h) is hooked while the editor runs; the original 3 bytes are restored on exit.
; Keys are decoded with the plain / SHIFT / CTRL tables (CTRL > SHIFT), auto-repeat after 20 frames, then every 3.
; Matrix: write E8h = (E8h & E0h) | 10h | column, read EAh (0 = pressed). Modifiers are in column 11:
;   D4 = CTRL, D2 = SHIFT (active low).
        section code_user
        public  _kbd_install
        public  _kbd_remove
        public  _kbd_get
        extern  kb_tab_plain
        extern  kb_tab_shift
        extern  kb_tab_ctrl

_kbd_install:
        di
        ld      hl,0038h
        ld      de,kb_orig
        ld      bc,3
        ldir                        ; save the original JP
        ld      a,0C3h
        ld      (0038h),a
        ld      hl,kbd_isr
        ld      (0039h),hl
        ld      hl,kb_prev
        ld      b,14
ki1:    ld      (hl),0FFh
        inc     hl
        djnz    ki1
        xor     a
        ld      (kb_head),a
        ld      (kb_tail),a
        ld      (kb_repv),a
        ei
        ret

_kbd_remove:
        di
        ld      hl,kb_orig
        ld      de,0038h
        ld      bc,3
        ldir
        ei
        ret

; int kbd_get(void): next key code or 0
_kbd_get:
        ld      a,(kb_tail)
        ld      hl,kb_head
        cp      (hl)
        jr      z,kg_empty
        ld      e,a
        ld      d,0
        ld      hl,kb_buf
        add     hl,de
        ld      l,(hl)
        ld      h,0
        ld      a,e
        inc     a
        and     15
        ld      (kb_tail),a
        ret
kg_empty:
        ld      hl,0
        ret

; ---------------------------------------------------------------- interrupt service
kbd_isr:
        push    af
        push    bc
        push    de
        push    hl
        ; --- scan 14 columns
        ld      hl,kb_cur
        ld      c,0
ks1:    in      a,(0E8h)
        and     0E0h
        or      10h
        or      c
        out     (0E8h),a
        nop
        nop
        in      a,(0EAh)
        ld      (hl),a
        inc     hl
        inc     c
        ld      a,c
        cp      14
        jr      nz,ks1
        ; --- choose table (CTRL > SHIFT > plain)
        ld      hl,kb_tab_plain
        ld      a,(kb_cur+11)
        bit     2,a
        jr      nz,ks2
        ld      hl,kb_tab_shift
ks2:    bit     4,a
        jr      nz,ks3
        ld      hl,kb_tab_ctrl
ks3:    ld      (kb_tabp),hl
        xor     a
        ld      (kb_newf),a
        ; --- new presses
        ld      c,0
kp1:    ld      a,c
        cp      11
        jr      z,kpn
        ld      e,c
        ld      d,0
        ld      hl,kb_cur
        add     hl,de
        ld      a,(hl)
        cpl                         ; 1 = pressed now
        ld      b,a
        ld      hl,kb_prev
        add     hl,de
        ld      a,(hl)              ; 1 = was released
        and     b
        jr      z,kpn
        ld      (kb_nb),a
        ld      hl,(kb_tabp)
        ld      a,c
        add     a,a
        add     a,a
        add     a,a
        ld      e,a
        ld      d,0
        add     hl,de               ; HL = table row for this column
        ld      a,(kb_nb)
        ld      b,8
kb1:    add     a,a                 ; D7 first
        jr      nc,kb2
        push    af
        ld      a,(hl)
        or      a
        jr      z,kb1x
        call    kb_put
        ld      (kb_repv),a
        ld      a,c
        ld      (kb_repc),a
        ld      a,8
        sub     b
        ld      (kb_repi),a
        xor     a
        ld      (kb_repn),a
        inc     a
        ld      (kb_newf),a
kb1x:   pop     af
kb2:    inc     hl
        djnz    kb1
kpn:    inc     c
        ld      a,c
        cp      14
        jr      nz,kp1
        ; --- auto repeat
        ld      a,(kb_newf)
        or      a
        jr      nz,kr_done
        ld      a,(kb_repv)
        or      a
        jr      z,kr_done
        ld      a,(kb_repc)
        ld      e,a
        ld      d,0
        ld      hl,kb_cur
        add     hl,de
        ld      a,(kb_repi)
        ld      b,a
        ld      a,(hl)
        inc     b
kr1:    dec     b
        jr      z,kr2
        add     a,a
        jr      kr1
kr2:    bit     7,a                 ; D(7-i): 1 = released
        jr      z,kr_held
        xor     a
        ld      (kb_repv),a
        jr      kr_done
kr_held:
        ld      a,(kb_repn)
        inc     a
        ld      (kb_repn),a
        cp      20
        jr      nz,kr_done
        ld      a,17
        ld      (kb_repn),a
        ld      a,(kb_repv)
        call    kb_put
kr_done:
        ; --- prev = cur
        ld      hl,kb_cur
        ld      de,kb_prev
        ld      bc,14
        ldir
        pop     hl
        pop     de
        pop     bc
        pop     af
        ei
        reti

; kb_put: A=code -> ring buffer (drops when full). Preserves all registers.
kb_put:
        push    af
        push    bc
        push    de
        push    hl
        ld      c,a
        ld      a,(kb_head)
        ld      e,a
        inc     a
        and     15
        ld      d,a
        ld      a,(kb_tail)
        cp      d
        jr      z,kbp_full
        ld      hl,kb_buf
        ld      b,0
        ld      a,e
        ld      e,a
        push    bc
        ld      c,e
        add     hl,bc
        pop     bc
        ld      (hl),c
        ld      a,d
        ld      (kb_head),a
kbp_full:
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret

; ---------------------------------------------------------------- state
kb_orig: defs   3
kb_prev: defs   14
kb_cur:  defs   14
kb_buf:  defs   16
kb_head: defb   0
kb_tail: defb   0
kb_tabp: defw   0
kb_nb:   defb   0
kb_newf: defb   0
kb_repv: defb   0
kb_repc: defb   0
kb_repi: defb   0
kb_repn: defb   0
