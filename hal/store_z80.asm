; store_z80.asm - banked text store for the MZ-2500: pages reserved with the LSX page API (07h-09h, then free extended-RAM pages 10h-1Fh), seen one at a time
; through bank 5 (A000h-BFFFh).  These pages are not mapped by LSX-Dodgers (banks 0..7 = 00,01,02,03,0A,0B,06,0F
; after boot; 0Ch/0Dh hold the MON copy of the IOCS RAM).  The editor image + stack must stay below A000h.
; Bank 5's original page is saved at init and restored at exit.
        section code_user
        public  _st_init_asm
        public  _st_exit_asm
        public  _st_get_asm
        public  _st_close
        public  _st_npg
        public  _st_capv
        public  _st_saveorig
        public  _st_mem
        extern  __BSS_END_tail
        public  _sv_read
        public  _sv_write
        public  _sv_off
        public  _sv_ptr
        public  _sv_n
        public  _sv_res
        public  _sv_c
        public  _sv_findb
        public  _sv_rfindb
        public  _sv_countb

PAGEIDX_NONE equ 0FFh

; _st_init_asm: decide where the text lives.
;   Page mode  : only if the OS is LSX (BDOS 6Fh gives L=4) AND the page API answers (E0h: A=0, HL=E000h).  Up to 6 pages are
;                reserved with E2h; every page is double-checked with E1h (owner must be 4 = reserved) and a pattern self-test
;                (fill, call the OS, verify).  Any failure -> release the pages and use memory mode.
;   Memory mode: a plain buffer in the TPA from the end of the image up to (0006h)-0800h.
; _st_saveorig: remember bank 5's page (also used by the file store)
_st_saveorig:
        ld      a,5
        out     (0B4h),a
        in      a,(0B5h)
        ld      (st_orig),a
        ld      a,PAGEIDX_NONE
        ld      (st_cur),a
        ret

_st_init_asm:
        call    _st_saveorig
        xor     a
        ld      (_st_npg),a
        ld      (_st_mem),a
        ld      c,6Fh               ; MSX-DOS-style version call; LSX/MZ-2500 answers L=4
        call    5
        ld      a,l
        cp      4
        jp      nz,si_mem
        ld      c,0E0h              ; SYSINFO: A=0 and HL=TPA top+1 if the page API exists
        call    5
        or      a
        jp      nz,si_mem
        ld      a,h
        cp      0E0h
        jp      nz,si_mem
        ; keep 7 pages free for E5h EXEC (a child needs 7) when the machine has enough: lim = free >= 9 ? min(6, free-7) : 6
        xor     a
        ld      (st_free),a
        ld      a,07h
        ld      (st_tmp),a
sl1:    ld      a,(st_tmp)
        ld      e,a
        ld      c,0E1h
        call    5
        ld      a,b
        or      a
        jr      nz,sl2
        ld      hl,st_free
        inc     (hl)
sl2:    ld      a,(st_tmp)
        inc     a
        ld      (st_tmp),a
        cp      20h
        jr      c,sl1
        ld      a,(st_free)
        ld      b,6
        cp      9
        jr      c,sl3
        sub     7
        cp      6
        jr      c,sl4
        ld      a,6
sl4:    ld      b,a
sl3:    ld      a,b
        ld      (st_lim),a
si_loop:
        ld      a,(st_lim)
        ld      b,a
        ld      a,(_st_npg)
        cp      b
        jr      z,si_done
        ld      c,0E2h              ; PAGEALLOC, E=FFh: lowest free page
        ld      e,0FFh
        call    5
        or      a
        jr      nz,si_done
        ld      a,b
        ld      (st_tmp),a
        ld      e,a
        ld      c,0E1h              ; PAGEINFO: owner must now be 4 (reserved)
        call    5
        ld      a,b
        cp      4
        jr      nz,si_bad1
        ld      a,(_st_npg)
        ld      e,a
        ld      d,0
        ld      hl,st_pgtab
        add     hl,de
        ld      a,(st_tmp)
        ld      (hl),a
        ld      a,e
        inc     a
        ld      (_st_npg),a
        jr      si_loop
si_bad1:                            ; page we could not confirm: give it back and stop
        ld      a,(st_tmp)
        ld      e,a
        ld      c,0E3h
        call    5
si_done:
        ld      a,(_st_npg)
        or      a
        jp      z,si_mem
        ; --- self test: fill every page with its own pattern, let the OS run, verify
        ld      b,a
        ld      c,0
st1:    push    bc
        ld      a,c
        call    st_map
        pop     bc
        push    bc
        ld      a,c
        add     a,a
        add     a,a
        xor     0A5h
        ld      hl,0A000h
        ld      (hl),a
        ld      de,0A001h
        ld      bc,1FFFh
        ldir
        pop     bc
        inc     c
        djnz    st1
        call    _st_close
        ld      c,0E0h              ; let the OS run
        call    5
        ld      a,(_st_npg)
        ld      b,a
        ld      c,0
st2:    push    bc
        ld      a,c
        call    st_map
        pop     bc
        push    bc
        ld      a,c
        add     a,a
        add     a,a
        xor     0A5h
        ld      hl,0A000h
        ld      bc,2000h
st3:    cpi
        jr      nz,st_fail
        jp      pe,st3
        pop     bc
        inc     c
        djnz    st2
        call    _st_close
        ld      a,(_st_npg)         ; capacity = pages * 8192
        rrca
        rrca
        rrca
        and     0E0h
        ld      h,a
        ld      l,0
        ld      (_st_capv),hl
        ret
st_fail:
        pop     bc
        call    _st_close
        call    _st_exit_asm        ; free the pages again
        xor     a
        ld      (_st_npg),a
si_mem:
        ld      a,1
        ld      (_st_mem),a
        ld      hl,__BSS_END_tail
        ld      (st_base),hl
        ld      hl,(0006h)
        ld      de,0800h
        or      a
        sbc     hl,de
        ld      de,(st_base)
        or      a
        sbc     hl,de
        jr      nc,sm1
        ld      hl,0
sm1:    ld      a,h
        cp      0C0h
        jr      c,sm2
        ld      hl,0C000h
sm2:    ld      (_st_capv),hl
        ret

; _st_close: give bank 5 back (call before any BDOS call) ; next access re-opens the window
_st_close:
        ld      a,5
        out     (0B4h),a
        ld      a,(st_orig)
        out     (0B5h),a
        ld      a,PAGEIDX_NONE
        ld      (st_cur),a
        ret

_st_exit_asm:
        call    _st_close
        ld      a,(_st_npg)
        ld      b,a
        or      a
        ret     z
        ld      hl,st_pgtab
se1:    push    bc
        push    hl
        ld      e,(hl)
        ld      c,0E3h              ; PAGEFREE (harmless if the page was an unreserved fallback)
        call    5
        pop     hl
        pop     bc
        inc     hl
        djnz    se1
        xor     a
        ld      (_st_npg),a
        ret

; st_map: A = page index (0..5) -> bank 5.  Clobbers A, DE, HL.
st_map:
        ld      (st_cur),a
        ld      e,a
        ld      d,0
        ld      hl,st_pgtab
        add     hl,de
        ld      a,5
        out     (0B4h),a
        ld      a,(hl)
        out     (0B5h),a
        ret

; u8 st_get(u16 i) __z88dk_fastcall : HL = i -> L = byte
_st_get_asm:
        ld      a,(_st_mem)
        or      a
        jr      z,sg0
        ld      de,(st_base)
        add     hl,de
        ld      l,(hl)
        ld      h,0
        ret
sg0:    ld      a,h
        rlca
        rlca
        rlca
        and     7
        ld      b,a
        ld      a,(st_cur)
        cp      b
        jr      z,sg1
        push    hl
        ld      a,b
        call    st_map
        pop     hl
sg1:    ld      a,h
        and     1Fh
        or      0A0h
        ld      h,a
        ld      l,(hl)
        ld      h,0
        ret

; common: compute window address/count for the next chunk.
;   in : sv_off, sv_n (n != 0)      out: DE = A000h+ofs (window address), BC = cnt, st_cnt = cnt
st_chunk:
        ld      a,(_st_mem)
        or      a
        jr      z,sc0
        ld      hl,(st_base)
        ld      de,(_sv_off)
        add     hl,de
        ex      de,hl               ; DE = base+off
        ld      bc,(_sv_n)
        ld      (st_cnt),bc
        ret
sc0:    ld      hl,(_sv_off)
        ld      a,h
        rlca
        rlca
        rlca
        and     7
        ld      hl,st_cur
        cp      (hl)
        call    nz,st_map
        ld      hl,(_sv_off)
        ld      a,h
        and     1Fh
        ld      h,a                 ; HL = offset inside the page (0..1FFFh)
        ld      de,2000h
        ex      de,hl               ; DE = ofs, HL = 2000h
        or      a
        sbc     hl,de               ; HL = room in this page
        ld      bc,(_sv_n)
        push    hl
        or      a
        sbc     hl,bc               ; room - n
        pop     hl
        jr      c,sc1               ; room < n -> cnt = room
        jr      sc2
sc1:    ld      b,h
        ld      c,l
sc2:    ld      (st_cnt),bc
        ld      hl,0A000h
        add     hl,de
        ex      de,hl               ; DE = window address
        ret

; after a chunk: advance sv_off and reduce sv_n by st_cnt
st_adv:
        ld      hl,(_sv_off)
        ld      bc,(st_cnt)
        add     hl,bc
        ld      (_sv_off),hl
        ld      hl,(_sv_n)
        or      a
        sbc     hl,bc
        ld      (_sv_n),hl
        ret

; void sv_read(void): store[sv_off..+sv_n) -> main memory at sv_ptr
_sv_read:
srd1:   ld      bc,(_sv_n)
        ld      a,b
        or      c
        ret     z
        call    st_chunk            ; DE = window address, BC = cnt
        ex      de,hl               ; HL = window source
        ld      de,(_sv_ptr)
        ldir
        ld      (_sv_ptr),de
        call    st_adv
        jr      srd1

; void sv_write(void): main memory at sv_ptr -> store[sv_off..+sv_n)
_sv_write:
swr1:   ld      bc,(_sv_n)
        ld      a,b
        or      c
        ret     z
        call    st_chunk            ; DE = window destination, BC = cnt
        ld      hl,(_sv_ptr)
        ldir
        ld      (_sv_ptr),hl
        call    st_adv
        jr      swr1

; ---------------------------------------------------------------- searching
; _sv_findb: first byte == sv_c in store[sv_off .. sv_off+sv_n) -> sv_res (0FFFFh if none)
_sv_findb:
        ld      hl,0FFFFh
        ld      (_sv_res),hl
fb1:    ld      bc,(_sv_n)
        ld      a,b
        or      c
        ret     z
        call    st_chunk            ; DE = window address, BC = cnt
        ex      de,hl
        ld      a,(_sv_c)
        cpir
        jr      z,fb2
        call    st_adv
        jr      fb1
fb2:    ld      hl,(st_cnt)         ; found: scanned = cnt - BC (includes the match)
        or      a
        sbc     hl,bc
        dec     hl
        ld      de,(_sv_off)
        add     hl,de
        ld      (_sv_res),hl
        ret

; _sv_countb: number of bytes == sv_c in store[sv_off .. sv_off+sv_n) -> sv_res
_sv_countb:
        ld      ix,0
cb1:    ld      bc,(_sv_n)
        ld      a,b
        or      c
        jr      z,cb9
        call    st_chunk
        ex      de,hl
        ld      a,(_sv_c)
cb2:    cpir
        jr      nz,cb3
        inc     ix
        ld      a,b
        or      c
        jr      z,cb3
        ld      a,(_sv_c)
        jr      cb2
cb3:    call    st_adv
        jr      cb1
cb9:    ld      (_sv_res),ix
        ret

; chunk for backward scans: sv_off = highest index to look at, sv_n = bytes left.
;   out: DE = window address of that byte, BC = cnt (bytes available going down in this page, <= sv_n), st_cnt = cnt
st_chunk_b:
        ld      a,(_st_mem)
        or      a
        jr      z,sb0
        ld      hl,(st_base)
        ld      de,(_sv_off)
        add     hl,de
        ex      de,hl
        ld      bc,(_sv_n)
        ld      (st_cnt),bc
        ret
sb0:    ld      hl,(_sv_off)
        ld      a,h
        rlca
        rlca
        rlca
        and     7
        ld      hl,st_cur
        cp      (hl)
        call    nz,st_map
        ld      hl,(_sv_off)
        ld      a,h
        and     1Fh
        ld      h,a                 ; HL = ofs in page
        push    hl
        inc     hl                  ; room = ofs + 1
        ld      bc,(_sv_n)
        push    hl
        or      a
        sbc     hl,bc
        pop     hl
        jr      c,sb1               ; room < n -> cnt = room
        jr      sb2
sb1:    ld      b,h
        ld      c,l
sb2:    ld      (st_cnt),bc
        pop     hl                  ; ofs
        ld      de,0A000h
        add     hl,de
        ex      de,hl               ; DE = window address
        ret

; _sv_rfindb: last byte == sv_c scanning down from sv_off for sv_n bytes -> sv_res (0FFFFh if none)
_sv_rfindb:
        ld      hl,0FFFFh
        ld      (_sv_res),hl
rb1:    ld      bc,(_sv_n)
        ld      a,b
        or      c
        ret     z
        call    st_chunk_b
        ex      de,hl
        ld      a,(_sv_c)
        cpdr
        jr      z,rb2
        ld      hl,(_sv_off)        ; not found in this chunk: move down
        ld      bc,(st_cnt)
        or      a
        sbc     hl,bc
        ld      (_sv_off),hl
        ld      hl,(_sv_n)
        or      a
        sbc     hl,bc
        ld      (_sv_n),hl
        jr      rb1
rb2:    ld      hl,(st_cnt)         ; found: scanned = cnt - BC; index = sv_off - scanned + 1
        or      a
        sbc     hl,bc
        ex      de,hl               ; DE = scanned
        ld      hl,(_sv_off)
        or      a
        sbc     hl,de
        inc     hl
        ld      (_sv_res),hl
        ret

st_pgtab:  defb 07h,08h,09h,0,0,0,0,0
_st_npg:   defb 0
_st_mem:   defb 0
_st_capv:  defw 0
st_base:   defw 0
st_tmp:    defb 0
st_free:   defb 0
st_lim:    defb 0
st_orig:   defb 0
st_cur:    defb 0FFh
st_cnt:    defw 0
_sv_off:   defw 0
_sv_ptr:   defw 0
_sv_n:     defw 0
_sv_res:   defw 0
_sv_c:     defb 0
