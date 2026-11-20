; vram_row.asm - write one 80-cell row to text VRAM (bank 7 window). Inputs via globals (C-callable, no args).
;   rw_adr = E000h + first cell (0..7FFh), rw_chars / rw_attrs = 80-byte arrays.
        section code_user
        public  _vram_row
        extern  _rw_adr
        extern  _rw_chars
        extern  _rw_attrs
_vram_row:
        di
        ld      a,7
        out     (0B4h),a
        ld      a,38h
        out     (0B5h),a
        ld      hl,(_rw_adr)
        ld      de,(_rw_chars)
        ld      ix,(_rw_attrs)
        ld      b,80
vr1:    ld      a,(de)
        inc     de
        ld      c,a
        add     a,a
        add     a,a
        ld      (hl),a              ; Text1
        set     3,h
        ld      a,(ix+0)
        inc     ix
        ld      (hl),a              ; attribute
        res     3,h
        set     4,h
        ld      a,c
        rlca
        rlca
        and     3
        or      8Ch
        ld      (hl),a              ; Text2
        res     4,h
        inc     hl
        ld      a,h
        cp      0E8h
        jr      nz,vr2
        ld      h,0E0h              ; wrap at 2048 cells
vr2:    djnz    vr1
        ld      a,7
        out     (0B4h),a
        ld      a,0Fh
        out     (0B5h),a
        ei
        ret

; crtc_start: wait (bounded) for vertical blanking, then load the text start address from _hw_start (cells).
        public  _crtc_start
        extern  _hw_start
_crtc_start:
        di
        ld      bc,30000
cs1:    in      a,(0F4h)
        and     1
        jr      z,cs2               ; b0 = 0 -> vblank
        dec     bc
        ld      a,b
        or      c
        jr      nz,cs1
cs2:    ld      hl,(_hw_start)
        ld      a,1
        out     (0F4h),a
        ld      a,l
        out     (0F5h),a
        ld      a,2
        out     (0F4h),a
        ld      a,h
        and     7
        out     (0F5h),a
        ei
        ret

; vram_clear: blank all 2048 cells (Text1=80h, attribute=07h, Text2=8Ch). Used before restoring start=0 on exit,
; so no scrolled-around picture is ever visible.
        public  _vram_clear
_vram_clear:
        di
        ld      a,7
        out     (0B4h),a
        ld      a,38h
        out     (0B5h),a
        ld      hl,0E800h           ; attribute = 00h (black) first: whatever glyph is left becomes invisible
        ld      (hl),00h
        ld      de,0E801h
        ld      bc,07FFh
        ldir
        ld      hl,0E000h           ; Text1 = 80h
        ld      (hl),80h
        ld      de,0E001h
        ld      bc,07FFh
        ldir
        ld      hl,0F000h           ; Text2 = 8Ch
        ld      (hl),8Ch
        ld      de,0F001h
        ld      bc,07FFh
        ldir
        ld      hl,0E800h           ; attribute = 07h (white), cells are blank now
        ld      (hl),07h
        ld      de,0E801h
        ld      bc,07FFh
        ldir
        ld      a,7
        out     (0B4h),a
        ld      a,0Fh
        out     (0B5h),a
        ei
        ret
