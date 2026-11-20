; exec_z80.asm - LSX-Dodgers E5h EXEC (run an external command, the editor's memory stays untouched)
        section code_user
        public  _exec_ok
        public  _exec_call

; u8 exec_ok(void): 1 if the OS is LSX (6Fh: L=4) with the page API at version 3 or later (E0h: E>=3, A=0)
_exec_ok:
        push    ix
        push    iy
        ld      c,6Fh
        call    5
        ld      a,l
        cp      4
        jr      nz,eo_no
        ld      c,0E0h
        call    5
        or      a
        jr      nz,eo_no
        ld      a,e
        cp      3
        jr      c,eo_no
        ld      hl,1
        jr      eo_end
eo_no:  ld      hl,0
eo_end: pop     iy
        pop     ix
        ret

; u8 exec_call(const char *cmd): E5h; the result of the child in L (0 = ok, 1 = failed, F0h = fewer than 7 free pages, F1h = nesting)
_exec_call:
        push    ix
        push    iy
        ld      hl,6                ; ret + iy + ix, then the argument
        add     hl,sp
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        ld      c,0E5h
        call    5
        ld      l,a
        ld      h,0
        pop     iy
        pop     ix
        ret
