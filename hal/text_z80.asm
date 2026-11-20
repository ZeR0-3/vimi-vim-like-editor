        section code_user
; text_z80.asm - the hot read-only paths of the block text layer (core/text_blk.c, built with -DTX_ASM), in Z80 asm.
; sccz80 turns every 32 bit pos_t operation into a library call; written by hand these shrink to about half.
; Same calling convention as sccz80 (smallc): arguments pushed left to right, the caller removes them, a long comes back in DE:HL
; (DE = high word), a u8 in L.  State shared with text_blk.c (not static there): ci, cs, nb, blen[], bph[], and nlc().
; ======================================================================================================================
; The rest of the block text layer (the asm twin of what was left in core/text_blk.c; the Z80 build no longer compiles that
; file, so the tables live here too).  tx_NB = blocks available for text (the last 3KB of the store are the aux area).
        public  _tx_aux_put, _tx_aux_get, _tx_aux_move, _tx_cap, _tx_adopt, _tx_reset, _tx_load_begin, _tx_load_chunk
        public  _tx_len, _tx_free, _tx_read, _tx_ins, _tx_del
        public  _blen, _bnl, _bph, _nb, _ci, _cs
        extern  _st_cap, _st_read, _st_write, _st_move
        defc    TX_NBMAX = 128
        defc    AUXBLK = 3                  ; TX_AUX / 1024

; DEHL = store address of byte BC of logical block HL
phx:
        push    bc
        call    baseI
        pop     bc
        add     hl,bc
        ret     nc
        inc     de
        ret
; HL = blen[HL]
blget:
        add     hl,hl
        ld      de,_blen
        add     hl,de
        ld      a,(hl)
        inc     hl
        ld      h,(hl)
        ld      l,a
        ret
; blen[HL] = DE
blput:
        push    de
        add     hl,hl
        ld      de,_blen
        add     hl,de
        pop     de
        ld      (hl),e
        inc     hl
        ld      (hl),d
        ret
; bnl[HL] = unknown
nlff:
        ld      de,_bnl
        add     hl,de
        ld      (hl),0FFh
        ret
; (HL) += BC / (HL) -= BC  (32 bit in memory)
add32:
        ld      a,(hl)
        add     a,c
        ld      (hl),a
        inc     hl
        ld      a,(hl)
        adc     a,b
        ld      (hl),a
        inc     hl
        ld      a,(hl)
        adc     a,0
        ld      (hl),a
        inc     hl
        ld      a,(hl)
        adc     a,0
        ld      (hl),a
        ret
sub32:
        ld      a,(hl)
        sub     c
        ld      (hl),a
        inc     hl
        ld      a,(hl)
        sbc     a,b
        ld      (hl),a
        inc     hl
        ld      a,(hl)
        sbc     a,0
        ld      (hl),a
        inc     hl
        ld      a,(hl)
        sbc     a,0
        ld      (hl),a
        ret
; drop HL = 12 bytes of arguments
pop12:
        pop     bc
        ld      hl,12
        add     hl,sp
        ld      sp,hl
        push    bc
        ret
; DEHL = A * 1024  (A <= 128)
shl10:
        ld      c,a
        rlca
        rlca
        and     3
        ld      e,a
        ld      d,0
        ld      a,c
        add     a,a
        add     a,a
        ld      h,a
        ld      l,0
        ret

; tx_NB = min(store size / 1024 - 3, 128)
setnb:
        call    _st_cap
        ld      l,h
        ld      h,e
        ld      a,d
        srl     a
        rr      h
        rr      l
        srl     a
        rr      h
        rr      l
        ld      de,AUXBLK
        or      a
        sbc     hl,de
        jr      nc,sn1
        ld      hl,0
sn1:
        ld      de,TX_NBMAX+1
        or      a
        sbc     hl,de
        add     hl,de
        jr      c,sn2
        ld      hl,TX_NBMAX
sn2:
        ld      (tx_NB),hl
        ret

; pos_t tx_cap(void) : the largest text a load may bring in = where the aux area starts
_tx_cap:
auxb:
        call    setnb
        ld      a,(tx_NB)
        jr      shl10
; DEHL = (ax_b) + BC
axadd:
        ld      hl,(ax_b)
        add     hl,bc
        ld      de,(ax_b+2)
        ret     nc
        inc     de
        ret
; BC = the word argument at SP + HL (as seen by the caller of this helper)
argw:
        inc     hl
        inc     hl
        add     hl,sp
        ld      c,(hl)
        inc     hl
        ld      b,(hl)
        ret

; void tx_aux_put(u16 off, const u8 *src, u16 n)
_tx_aux_put:
        call    auxb
        ld      (ax_b),hl
        ld      (ax_b+2),de
        ld      hl,6
        call    argw
        call    axadd
        push    de
        push    hl
        ld      hl,8
        call    argw
        push    bc
        ld      bc,0
        push    bc
        ld      hl,10
        call    argw
        push    bc
        call    _st_write
        jr      pop5
; void tx_aux_get(u8 *dst, u16 off, u16 n)
_tx_aux_get:
        call    auxb
        ld      (ax_b),hl
        ld      (ax_b+2),de
        ld      hl,6
        call    argw
        push    bc
        ld      hl,6
        call    argw
        call    axadd
        push    de
        push    hl
        ld      bc,0
        push    bc
        ld      hl,10
        call    argw
        push    bc
        call    _st_read
pop5:
        pop     bc
        pop     bc
        pop     bc
        pop     bc
        pop     bc
        ret
; void tx_aux_move(u16 dst, u16 src, u16 n)
_tx_aux_move:
        call    auxb
        ld      (ax_b),hl
        ld      (ax_b+2),de
        ld      hl,6
        call    argw
        call    axadd
        push    de
        push    hl
        ld      hl,8
        call    argw
        call    axadd
        push    de
        push    hl
        ld      bc,0
        push    bc
        ld      hl,12
        call    argw
        push    bc
        call    _st_move
        call    pop12
        ret

; pos_t tx_len(void) / pos_t tx_free(void)
_tx_len:
        ld      hl,(tx_total)
        ld      de,(tx_total+2)
        ret
_tx_free:
        ld      hl,(tx_NB)
        ld      de,(_nb)
        or      a
        sbc     hl,de
        ld      de,2
        or      a
        sbc     hl,de
        ld      a,l
        jp      nc,shl10
        xor     a
        jp      shl10

; void tx_reset(void) / void tx_adopt(pos_t n) : the store holds n bytes of text from offset 0
_tx_reset:
        xor     a
        ld      (tx_hint),a
        ld      h,a
        ld      l,a
        ld      d,a
        ld      e,a
        jr      adopt
_tx_adopt:
        ld      hl,2
        add     hl,sp
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        inc     hl
        ld      a,(hl)
        inc     hl
        ld      h,(hl)
        ld      l,a
        ex      de,hl
adopt:
        ld      (tx_total),hl
        ld      (tx_total+2),de
        call    setnb
        ld      hl,(tx_total)
        ld      de,(tx_total+2)
        ld      a,h
        or      l
        or      d
        or      e
        jr      nz,ad1
        ld      hl,1
        ld      (_nb),hl
        dec     hl
        ld      (ad_last),hl
        jr      ad2
ad1:
        ld      a,h                 ; nb = ceil(n / 1024)
        ld      b,l
        ld      l,a
        ld      h,e
        srl     h
        rr      l
        srl     h
        rr      l
        and     3
        or      b
        jr      z,ad1a
        inc     hl
ad1a:
        ld      (_nb),hl
        ld      hl,(tx_total)       ; bytes in the last block
        dec     hl
        ld      a,h
        and     3
        ld      h,a
        inc     hl
        ld      (ad_last),hl
ad2:
        ld      bc,0
ad3:
        ld      hl,(tx_NB)
        or      a
        sbc     hl,bc
        jr      z,ad9
        ld      hl,_bph
        add     hl,bc
        ld      (hl),c
        ld      a,(tx_hint)
        or      a
        jr      nz,ad4
        ld      hl,_bnl
        add     hl,bc
        ld      (hl),0FFh
ad4:
        ld      h,b
        ld      l,c
        inc     hl
        ld      de,(_nb)
        or      a
        sbc     hl,de
        ld      de,1024
        jr      c,ad5
        ld      de,(ad_last)
        jr      z,ad5
        ld      de,0
ad5:
        ld      h,b
        ld      l,c
        call    blput
        inc     bc
        jr      ad3
ad9:
        ld      hl,0
        ld      (_ci),hl
        ld      (_cs),hl
        ld      (_cs+2),hl
        xor     a
        ld      (tx_hint),a
        ret

; void tx_load_begin(void) / void tx_load_chunk(pos_t off, const u8 *buf, u16 k) : count the line breaks of each block
; while the file is being loaded (so that the first G / line number costs nothing)
_tx_load_begin:
        ld      hl,_bnl
        ld      de,_bnl+1
        ld      (hl),0
        ld      bc,TX_NBMAX-1
        ldir
        ld      a,1
        ld      (tx_hint),a
        ret
_tx_load_chunk:
        ld      hl,2
        add     hl,sp
        ld      c,(hl)
        inc     hl
        ld      b,(hl)
        inc     hl
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        inc     hl
        push    de
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        inc     hl
        ld      a,(hl)
        ld      (lc_h),a
        pop     hl                  ; HL = buf, DE = low word of off, lc_h = its bits 16..23, BC = k
lc1:
        ld      a,b
        or      c
        ret     z
        dec     bc
        ld      a,(hl)
        inc     hl
        cp      10
        jr      nz,lc3
        push    hl
        ld      a,(lc_h)
        cp      2
        jr      nc,lc2
        rrca
        rrca
        ld      l,a
        ld      a,d
        srl     a
        srl     a
        or      l
        ld      l,a
        ld      h,0
        push    de
        ld      de,_bnl
        add     hl,de
        pop     de
        ld      a,(hl)
        cp      0FEh
        jr      nc,lc1a
        inc     a
        jr      lc1b
lc1a:
        ld      a,0FFh
lc1b:
        ld      (hl),a
lc2:
        pop     hl
lc3:
        inc     de
        ld      a,d
        or      e
        jr      nz,lc1
        push    hl
        ld      hl,lc_h
        inc     (hl)
        pop     hl
        jr      lc1

; void tx_read(u8 *dst, pos_t p, pos_t n)
_tx_read:
        ld      hl,2
        add     hl,sp
        ld      de,rd_n
        ld      bc,10
        ldir
rd1:
        ld      hl,(rd_n)
        ld      a,h
        or      l
        ld      hl,(rd_n+2)
        or      h
        or      l
        ret     z
        ld      hl,(rd_p)
        ld      de,(rd_p+2)
        call    loc
        ld      hl,(rd_p)
        ld      de,(_cs)
        or      a
        sbc     hl,de
        ld      (rd_o),hl
        call    blen_ci
        ex      de,hl
        ld      de,(rd_o)
        or      a
        sbc     hl,de
        ld      de,(rd_n+2)
        ld      a,d
        or      e
        jr      nz,rd2
        ld      de,(rd_n)
        or      a
        sbc     hl,de
        add     hl,de
        jr      c,rd2
        ex      de,hl
rd2:
        ld      (rd_k),hl
        ld      hl,(rd_dst)
        push    hl
        ld      hl,(_ci)
        ld      bc,(rd_o)
        call    phx
        push    de
        push    hl
        ld      hl,0
        push    hl
        ld      hl,(rd_k)
        push    hl
        call    _st_read
        pop     bc
        pop     bc
        pop     bc
        pop     bc
        pop     bc
        ld      bc,(rd_k)
        ld      hl,(rd_dst)
        add     hl,bc
        ld      (rd_dst),hl
        ld      hl,rd_p
        call    add32
        ld      hl,rd_n
        call    sub32
        jr      rd1

; fold block HL+1 into block HL when both fit in one block
mrg:
        ld      (mg_i),hl
        inc     hl
        ld      de,(_nb)
        or      a
        sbc     hl,de
        ret     nc
        ld      hl,(mg_i)
        call    blget
        ld      (mg_a),hl
        ld      hl,(mg_i)
        inc     hl
        call    blget
        ld      (mg_b),hl
        ld      de,(mg_a)
        add     hl,de
        ld      de,1025
        or      a
        sbc     hl,de
        ret     nc
        ld      hl,(mg_i)
        ld      bc,(mg_a)
        call    phx
        push    de
        push    hl
        ld      hl,(mg_i)
        inc     hl
        ld      bc,0
        call    phx
        push    de
        push    hl
        ld      hl,0
        push    hl
        ld      hl,(mg_b)
        push    hl
        call    _st_move
        call    pop12
        ld      hl,(mg_a)
        ld      de,(mg_b)
        add     hl,de
        ex      de,hl
        ld      hl,(mg_i)
        call    blput
        ld      hl,(mg_i)
        call    nlff
        ld      hl,(mg_i)
        inc     hl
        push    hl
        call    _remove_block
        pop     bc
        ret

; st_write(ph(ci, BC), in_src, DE)
wr:
        ld      (in_k),de
        ld      hl,(_ci)
        call    phx
        push    de
        push    hl
        ld      hl,(in_src)
        push    hl
        ld      hl,0
        push    hl
        ld      hl,(in_k)
        push    hl
        call    _st_write
        jp      pop5
; blen[ci] = DE, its line count unknown
setbl:
        ld      hl,(_ci)
        call    blput
        ld      hl,(_ci)
        jp      nlff

; u8 tx_ins(pos_t p, const u8 *src, pos_t n) : 0 = no room (n < 64KB)
_tx_ins:
        ld      hl,2
        add     hl,sp
        ld      de,in_n
        ld      bc,10
        ldir
        ld      hl,(in_n)
        ld      de,(in_n+2)
        ld      a,d
        or      e
        jr      nz,in_no
        or      h
        or      l
        jr      nz,in1
in_yes:
        ld      hl,1
        ret
in_no:
        ld      hl,0
        ret
in1:
        ld      hl,(in_p)
        ld      de,(in_p+2)
        call    loc
        ld      hl,(in_p)
        ld      de,(_cs)
        or      a
        sbc     hl,de
        ld      (in_off),hl
        call    blen_ci
        ld      (in_bl),de
        ld      hl,1024
        or      a
        sbc     hl,de
        ld      de,(in_n)
        or      a
        sbc     hl,de
        jr      c,in_big
        ld      hl,(in_off)         ; it fits in this block: make room, write
        ld      de,(in_bl)
        or      a
        sbc     hl,de
        jr      nc,in2
        ld      hl,(in_off)
        ld      de,(in_n)
        add     hl,de
        ld      b,h
        ld      c,l
        ld      hl,(_ci)
        call    phx
        push    de
        push    hl
        ld      hl,(_ci)
        ld      bc,(in_off)
        call    phx
        push    de
        push    hl
        ld      hl,0
        push    hl
        ld      hl,(in_bl)
        ld      de,(in_off)
        or      a
        sbc     hl,de
        push    hl
        call    _st_move
        call    pop12
in2:
        ld      bc,(in_off)
        ld      de,(in_n)
        call    wr
        ld      hl,(in_bl)
        ld      de,(in_n)
        add     hl,de
        ex      de,hl
        call    setbl
        ld      bc,(in_n)
        ld      hl,tx_total
        call    add32
        jp      in_yes
in_big:
        ld      a,(in_n+1)          ; enough free blocks?  (n / 1024 + 2)
        srl     a
        srl     a
        add     a,2
        ld      e,a
        ld      d,0
        ld      hl,(tx_NB)
        ld      bc,(_nb)
        or      a
        sbc     hl,bc
        or      a
        sbc     hl,de
        jp      c,in_no
        ld      hl,(in_off)
        ld      de,(in_bl)
        or      a
        sbc     hl,de
        jr      nc,in5
        ld      hl,(in_bl)          ; the part after p moves into a block of its own
        ld      de,(in_off)
        or      a
        sbc     hl,de
        ld      (in_tl),hl
        ld      hl,(_nb)
        ld      bc,0
        call    phx
        push    de
        push    hl
        ld      hl,(_ci)
        ld      bc,(in_off)
        call    phx
        push    de
        push    hl
        ld      hl,0
        push    hl
        ld      hl,(in_tl)
        push    hl
        call    _st_move
        call    pop12
        ld      hl,(_ci)
        inc     hl
        push    hl
        ld      hl,(in_tl)
        push    hl
        call    _insert_block
        pop     bc
        pop     bc
        ld      de,(in_off)
        call    setbl
in5:
        ld      hl,(in_n)           ; fill this block, then new ones
        ld      a,h
        or      l
        jp      z,in_yes
        call    blen_ci
        ld      hl,1024
        or      a
        sbc     hl,de
        ld      de,(in_n)
        or      a
        sbc     hl,de
        add     hl,de
        jr      c,in6
        ex      de,hl
in6:
        ld      a,h
        or      l
        jr      z,in7
        push    hl
        call    blen_ci
        ld      b,d
        ld      c,e
        pop     de
        call    wr
        call    blen_ci
        ld      hl,(in_k)
        add     hl,de
        ex      de,hl
        call    setbl
        ld      bc,(in_k)
        ld      hl,tx_total
        call    add32
        ld      hl,(in_src)
        ld      de,(in_k)
        add     hl,de
        ld      (in_src),hl
        ld      hl,(in_n)
        or      a
        sbc     hl,de
        ld      (in_n),hl
in7:
        ld      hl,(in_n)
        ld      a,h
        or      l
        jp      z,in_yes
        ld      hl,(_ci)
        inc     hl
        push    hl
        ld      hl,0
        push    hl
        call    _insert_block
        pop     bc
        pop     bc
        call    blen_ci
        ld      b,d
        ld      c,e
        ld      hl,_cs
        call    add32
        ld      hl,(_ci)
        inc     hl
        ld      (_ci),hl
        jr      in5

; void tx_del(pos_t p, pos_t n)
_tx_del:
        ld      hl,2
        add     hl,sp
        ld      de,dl_n
        ld      bc,8
        ldir
dl1:
        ld      hl,(dl_n)
        ld      a,h
        or      l
        ld      hl,(dl_n+2)
        or      h
        or      l
        ret     z
        ld      hl,(dl_p)
        ld      de,(dl_p+2)
        call    loc
        ld      hl,(dl_p)
        ld      de,(_cs)
        or      a
        sbc     hl,de
        ld      (in_off),hl
        call    blen_ci
        ld      (in_bl),de
        ex      de,hl
        ld      de,(in_off)
        or      a
        sbc     hl,de               ; the rest of this block
        ld      de,(dl_n+2)
        ld      a,d
        or      e
        jr      nz,dl2
        ld      de,(dl_n)
        or      a
        sbc     hl,de
        add     hl,de
        jr      c,dl2
        ex      de,hl
dl2:
        ld      (in_k),hl
        ld      a,h
        or      l
        ret     z
        ex      de,hl
        ld      hl,(in_off)
        add     hl,de
        ld      (in_tl),hl          ; off + k
        ld      de,(in_bl)
        or      a
        sbc     hl,de
        jr      nc,dl3
        ld      hl,(_ci)            ; close the gap
        ld      bc,(in_off)
        call    phx
        push    de
        push    hl
        ld      hl,(_ci)
        ld      bc,(in_tl)
        call    phx
        push    de
        push    hl
        ld      hl,0
        push    hl
        ld      hl,(in_bl)
        ld      de,(in_tl)
        or      a
        sbc     hl,de
        push    hl
        call    _st_move
        call    pop12
dl3:
        ld      hl,(in_bl)
        ld      de,(in_k)
        or      a
        sbc     hl,de
        ex      de,hl
        call    setbl
        ld      bc,(in_k)
        ld      hl,tx_total
        call    sub32
        ld      bc,(in_k)
        ld      hl,dl_n
        call    sub32
        call    blen_ci
        ld      a,d
        or      e
        jr      nz,dl5
        ld      hl,(_nb)
        dec     hl
        ld      a,h
        or      l
        jr      z,dl5
        ld      hl,(_ci)            ; the block is empty: drop it
        push    hl
        call    _remove_block
        pop     bc
        ld      hl,(_ci)
        ld      de,(_nb)
        or      a
        sbc     hl,de
        jp      c,dl1
        dec     de                  ; it was the last one: the cache moves to the new last block
        ld      (_ci),de
        call    blen_ci
        ld      hl,(tx_total)
        or      a
        sbc     hl,de
        ld      (_cs),hl
        ld      hl,(tx_total+2)
        ld      de,0
        sbc     hl,de
        ld      (_cs+2),hl
        jp      dl1
dl5:
        ld      hl,(_ci)            ; merge with the neighbours when they fit in one block
        call    mrg
        ld      hl,(_ci)
        ld      a,h
        or      l
        jp      z,dl1
        dec     hl
        call    blget
        push    hl
        call    blen_ci
        pop     hl
        add     hl,de
        ld      de,1025
        or      a
        sbc     hl,de
        jp      nc,dl1
        ld      hl,(_ci)
        dec     hl
        ld      (_ci),hl
        call    blen_ci
        ld      b,d
        ld      c,e
        ld      hl,_cs
        call    sub32
        ld      hl,(_ci)
        call    mrg
        jp      dl1

        section code_user
        public  _locate
        public  _ph
        public  _nlc
        public  _tx_nthline
        public  _insert_block
        public  _remove_block
        public  _tx_get
        public  _tx_find
        public  _tx_rfind
        public  _tx_count
        extern  _st_get
        extern  _st_findb
        extern  _st_rfindb
        extern  _st_countb

; DE = blen[ci]  (clobbers HL)
blen_ci:
        ld      hl,(_ci)
        add     hl,hl
        ld      de,_blen
        add     hl,de
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        ret

; HL = low word, DE = high word of the store address of block ci (bph[ci] * 1024); clobbers A
base:
        ld      hl,(_ci)
baseI:                              ; HL = block index
        ld      de,_bph
        add     hl,de
        ld      a,(hl)
        ld      h,a
        rlca
        rlca
        and     3
        ld      e,a
        ld      d,0
        ld      a,h
        and     3Fh
        add     a,a
        add     a,a
        ld      h,a
        ld      l,0
        ret

; HL:DE = (bb) + BC   (the base address saved by the caller plus a 16 bit offset)
bpo:
        ld      hl,(bb)
        add     hl,bc
        ld      de,(bb+2)
        ret     nc
        inc     de
        ret

; ci/cs := the block holding p.  in: DE:HL = p (high:low)
loc:
        ld      (lp),hl
        ld      (lp+2),de
loc1:
        ld      hl,(_ci)
        ld      a,h
        or      l
        jr      z,loc2
        ld      hl,(lp)
        ld      de,(_cs)
        or      a
        sbc     hl,de
        ld      hl,(lp+2)
        ld      de,(_cs+2)
        sbc     hl,de
        jr      nc,loc2             ; p >= cs
        ld      hl,(_ci)
        dec     hl
        ld      (_ci),hl
        call    blen_ci
        ld      hl,(_cs)
        or      a
        sbc     hl,de
        ld      (_cs),hl
        jr      nc,loc1
        ld      hl,(_cs+2)
        dec     hl
        ld      (_cs+2),hl
        jr      loc1
loc2:
        ld      hl,(_ci)
        inc     hl
        ld      de,(_nb)
        or      a
        sbc     hl,de
        ret     nc                  ; this is the last block
        call    blen_ci
        ld      hl,(_cs)
        add     hl,de
        ld      (le),hl
        ld      hl,(_cs+2)
        ld      de,0
        adc     hl,de
        ld      (le+2),hl           ; le = cs + blen[ci]
        ld      hl,(lp)
        ld      de,(le)
        or      a
        sbc     hl,de
        ld      hl,(lp+2)
        ld      de,(le+2)
        sbc     hl,de
        ret     c                   ; p < le: found
        ld      hl,(le)
        ld      (_cs),hl
        ld      hl,(le+2)
        ld      (_cs+2),hl
        ld      hl,(_ci)
        inc     hl
        ld      (_ci),hl
        jr      loc2

; void locate(pos_t p)
_locate:
        push    ix
        ld      ix,0
        add     ix,sp
        ld      l,(ix+4)
        ld      h,(ix+5)
        ld      e,(ix+6)
        ld      d,(ix+7)
        call    loc
        pop     ix
        ret

; u8 tx_get(pos_t i)
_tx_get:
        push    ix
        ld      ix,0
        add     ix,sp
        ld      l,(ix+4)
        ld      h,(ix+5)
        ld      e,(ix+6)
        ld      d,(ix+7)
        call    loc
        ld      hl,(lp)
        ld      de,(_cs)
        or      a
        sbc     hl,de
        push    hl                  ; offset inside the block
        call    base
        pop     bc
        add     hl,bc
        jr      nc,tg1
        inc     de
tg1:
        push    de
        push    hl
        call    _st_get
        pop     bc
        pop     bc
        ld      h,0
        pop     ix
        ret

; pos_t ph(u16 i, u16 off): store address of byte off of logical block i
_ph:
        ld      hl,4
        add     hl,sp
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        ld      hl,2
        add     hl,sp
        ld      c,(hl)
        inc     hl
        ld      b,(hl)
        ex      de,hl
        push    bc
        call    baseI
        pop     bc
        add     hl,bc
        ret     nc
        inc     de
        ret

; seg: locate p (ix+10) and cut the range at the end of the block / at end (ix+6): so0 = start offset in the block, so1 = end offset
seg:
        ld      l,(ix+10)
        ld      h,(ix+11)
        ld      e,(ix+12)
        ld      d,(ix+13)
        call    loc
        ld      hl,(lp)
        ld      de,(_cs)
        or      a
        sbc     hl,de
        ld      (so0),hl
        ld      l,(ix+6)
        ld      h,(ix+7)
        ld      de,(_cs)
        or      a
        sbc     hl,de
        ld      (so1),hl            ; end - cs, low word
        ld      l,(ix+8)
        ld      h,(ix+9)
        ld      de,(_cs+2)
        sbc     hl,de
        ld      a,h
        or      l
        jr      nz,seg_full         ; end is far away: the whole rest of the block
        call    blen_ci
        ld      hl,(so1)
        or      a
        sbc     hl,de
        jr      nc,seg_full         ; end - cs >= blen
        ret                         ; so1 = end - cs already
seg_full:
        call    blen_ci
        ld      (so1),de
        ret

; p := cs + so1 (p at ix+10)
nextp:
        ld      hl,(_cs)
        ld      bc,(so1)
        add     hl,bc
        ld      (ix+10),l
        ld      (ix+11),h
        ld      hl,(_cs+2)
        jr      nc,np1
        inc     hl
np1:
        ld      (ix+12),l
        ld      (ix+13),h
        ret

; in: p < end ?  returns carry set if p < end  (p at ix+10, end at ix+6)
lessend:
        ld      l,(ix+10)
        ld      h,(ix+11)
        ld      e,(ix+6)
        ld      d,(ix+7)
        or      a
        sbc     hl,de
        ld      l,(ix+12)
        ld      h,(ix+13)
        ld      e,(ix+8)
        ld      d,(ix+9)
        sbc     hl,de
        ret

; pos_t tx_find(pos_t p, pos_t end, u8 c)
_tx_find:
        push    ix
        ld      ix,0
        add     ix,sp
tf_lp:
        call    lessend
        jr      nc,tf_end
        call    seg
        call    base
        ld      (bb),hl
        ld      (bb+2),de
        ld      bc,(so1)
        call    bpo
        ld      (sp1),hl
        ld      (sp1+2),de
        ld      bc,(so0)
        call    bpo
        push    de
        push    hl                  ; start
        ld      hl,(sp1+2)
        push    hl
        ld      hl,(sp1)
        push    hl                  ; stop
        ld      l,(ix+4)
        ld      h,0
        push    hl
        call    _st_findb
        pop     bc
        pop     bc
        pop     bc
        pop     bc
        pop     bc
        ld      ix,0
        add     ix,sp
        ld      bc,(bb)
        or      a
        sbc     hl,bc               ; index of the hit inside the block
        ld      de,(so1)
        push    hl
        or      a
        sbc     hl,de
        pop     hl
        jr      z,tf_next           ; hit == stop: not in this block
        ld      de,(_cs)
        add     hl,de
        ld      de,(_cs+2)
        jr      nc,tf_f2
        inc     de
tf_f2:
        pop     ix
        ret
tf_next:
        call    nextp
        jr      tf_lp
tf_end:
        ld      l,(ix+6)
        ld      h,(ix+7)
        ld      e,(ix+8)
        ld      d,(ix+9)
        pop     ix
        ret

; pos_t tx_count(pos_t a, pos_t e, u8 c)
_tx_count:
        push    ix
        ld      ix,0
        add     ix,sp
        ld      hl,0
        ld      (cn),hl
        ld      (cn+2),hl
tc_lp:
        call    lessend
        jp      nc,tc_end
        call    seg
        ld      a,(ix+4)
        cp      0Ah
        jr      nz,tc_scan
        ld      hl,(so0)
        ld      a,h
        or      l
        jr      nz,tc_scan
        call    blen_ci
        ld      hl,(so1)
        or      a
        sbc     hl,de
        jr      nz,tc_scan
        ld      hl,(_ci)            ; the whole block: its cached newline count
        push    hl
        call    _nlc
        pop     bc
        ld      ix,0
        add     ix,sp
        jr      tc_add
tc_scan:
        call    base
        ld      (bb),hl
        ld      (bb+2),de
        ld      bc,(so1)
        call    bpo
        ld      (sp1),hl
        ld      (sp1+2),de
        ld      bc,(so0)
        call    bpo
        push    de
        push    hl
        ld      hl,(sp1+2)
        push    hl
        ld      hl,(sp1)
        push    hl
        ld      l,(ix+4)
        ld      h,0
        push    hl
        call    _st_countb
        pop     bc
        pop     bc
        pop     bc
        pop     bc
        pop     bc
        ld      ix,0
        add     ix,sp
tc_add:                             ; cn += HL
        ld      de,(cn)
        add     hl,de
        ld      (cn),hl
        jr      nc,tc_nx
        ld      hl,(cn+2)
        inc     hl
        ld      (cn+2),hl
tc_nx:
        call    nextp
        jp      tc_lp
tc_end:
        ld      hl,(cn)
        ld      de,(cn+2)
        pop     ix
        ret

; pos_t tx_rfind(pos_t p, u8 c)
_tx_rfind:
        push    ix
        ld      ix,0
        add     ix,sp
tr_lp:
        ld      a,(ix+6)
        or      (ix+7)
        or      (ix+8)
        or      (ix+9)
        jp      z,tr_none
        ld      l,(ix+6)
        ld      h,(ix+7)
        ld      e,(ix+8)
        ld      d,(ix+9)
        ld      a,h
        or      l
        dec     hl
        jr      nz,tr_l1
        dec     de
tr_l1:
        call    loc                 ; the block holding p-1
        ld      l,(ix+6)
        ld      h,(ix+7)
        ld      de,(_cs)
        or      a
        sbc     hl,de
        ld      (so0),hl            ; p - cs
        call    base
        ld      (bb),hl
        ld      (bb+2),de
        ld      bc,(so0)
        call    bpo
        push    de
        push    hl                  ; start
        ld      hl,(bb+2)
        push    hl
        ld      hl,(bb)
        push    hl                  ; floor = block start
        ld      l,(ix+4)
        ld      h,0
        push    hl
        call    _st_rfindb
        pop     bc
        pop     bc
        pop     bc
        pop     bc
        pop     bc
        ld      ix,0
        add     ix,sp
        ld      a,h
        and     l
        and     d
        and     e
        inc     a
        jr      nz,tr_hit
        ld      hl,(_cs)            ; not in this block: continue with p := cs
        ld      (ix+6),l
        ld      (ix+7),h
        ld      hl,(_cs+2)
        ld      (ix+8),l
        ld      (ix+9),h
        jr      tr_lp
tr_hit:
        ld      bc,(bb)
        or      a
        sbc     hl,bc
        ld      de,(_cs)
        add     hl,de
        ld      de,(_cs+2)
        jr      nc,tr_h2
        inc     de
tr_h2:
        pop     ix
        ret
tr_none:
        ld      hl,0FFFFh
        ld      de,0FFFFh
        pop     ix
        ret


; u16 nlc(u16 i): newlines in logical block i (cached in bnl[], 0FFh = not known / 255 or more)
_nlc:
        push    ix
        ld      ix,0
        add     ix,sp
        ld      l,(ix+4)
        ld      h,(ix+5)
        ld      de,_bnl
        add     hl,de
        ld      a,(hl)
        cp      0FFh
        jr      z,nlc1
        ld      l,a
        ld      h,0
        pop     ix
        ret
nlc1:
        ld      l,(ix+4)
        ld      h,(ix+5)
        call    baseI
        push    de
        push    hl                  ; start of the block
        ld      l,(ix+4)
        ld      h,(ix+5)
        add     hl,hl
        ld      de,_blen
        add     hl,de
        ld      c,(hl)
        inc     hl
        ld      b,(hl)              ; BC = blen[i]
        push    bc
        ld      l,(ix+4)
        ld      h,(ix+5)
        call    baseI
        pop     bc
        add     hl,bc
        jr      nc,nlc2
        inc     de
nlc2:
        push    de
        push    hl                  ; end of the data
        ld      hl,0Ah
        push    hl
        call    _st_countb
        pop     bc
        pop     bc
        pop     bc
        pop     bc
        pop     bc
        ld      ix,0                ; st_countb clobbers IX
        add     ix,sp
        ld      a,h
        or      a
        jr      nz,nlc_big
        ld      a,l
        cp      0FFh
        jr      nc,nlc_big
        push    hl
        ld      l,(ix+4)
        ld      h,(ix+5)
        ld      de,_bnl
        add     hl,de
        ld      (hl),a
        pop     hl
nlc_big:
        pop     ix                  ; (also restores IX, which the OS may have changed)
        ret

; pos_t tx_nthline(pos_t n): start of line n (1-based); beyond the end = the last line
_tx_nthline:
        push    ix
        ld      ix,0
        add     ix,sp
        ld      hl,0
        ld      (tt),hl
        ld      (tt+2),hl
        ld      (ni),hl
nt1:
        ld      hl,(ni)
        ld      de,(_nb)
        or      a
        sbc     hl,de
        jr      nc,nt2
        ld      hl,(ni)
        push    hl
        call    _nlc
        pop     bc
        ld      de,(tt)
        add     hl,de
        ld      (tt),hl
        jr      nc,nt1a
        ld      hl,(tt+2)
        inc     hl
        ld      (tt+2),hl
nt1a:
        ld      hl,(ni)
        inc     hl
        ld      (ni),hl
        jr      nt1
nt2:
        ld      hl,(tt)
        ld      de,(tt+2)
        ld      a,h
        or      l
        or      d
        or      e
        jp      z,nt_zero           ; no newline at all
        ld      l,(ix+4)
        ld      h,(ix+5)
        ld      e,(ix+6)
        ld      d,(ix+7)
        ld      a,d
        or      e
        jr      nz,nt3
        ld      a,h
        or      a
        jr      nz,nt3
        ld      a,l
        cp      2
        jp      c,nt_zero           ; n <= 1
nt3:
        ld      a,h                 ; k = n - 1
        or      l
        dec     hl
        jr      nz,nt3a
        dec     de
nt3a:
        ld      (nk),hl
        ld      (nk+2),de
        ld      hl,(nk)             ; if (k >= tot) k = tot - 1
        ld      de,(tt)
        or      a
        sbc     hl,de
        ld      hl,(nk+2)
        ld      de,(tt+2)
        sbc     hl,de
        jr      c,nt3b
        ld      hl,(tt)
        ld      de,(tt+2)
        ld      a,h
        or      l
        dec     hl
        jr      nz,nt3c
        dec     de
nt3c:
        ld      (nk),hl
        ld      (nk+2),de
nt3b:
        ld      hl,0
        ld      (nat),hl
        ld      (nat+2),hl
        ld      (ni),hl
nt4:
        ld      hl,(ni)
        ld      de,(_nb)
        or      a
        sbc     hl,de
        jp      nc,nt_zero
        ld      hl,(nk)
        ld      de,(nk+2)
        ld      a,h
        or      l
        or      d
        or      e
        jp      z,nt_zero
        ld      hl,(ni)
        push    hl
        call    _nlc
        pop     bc
        ld      (nc),hl
        ld      hl,(ni)
        add     hl,hl
        ld      de,_blen
        add     hl,de
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        ld      (nbl),de
        ld      hl,(nk+2)
        ld      a,h
        or      l
        jr      nz,nt5              ; k >= 65536 > c
        ld      hl,(nc)
        ld      de,(nk)
        or      a
        sbc     hl,de
        jr      c,nt5               ; c < k
        ld      hl,(ni)             ; the line is in this block: skip k newlines inside it
        call    baseI
        ld      (nb0),hl
        ld      (nb0+2),de
        ld      hl,0
        ld      (no),hl
        ld      hl,(nk)
        ld      (nc),hl
nt6:
        ld      hl,(nb0)
        ld      bc,(no)
        add     hl,bc
        ld      de,(nb0+2)
        jr      nc,nt6a
        inc     de
nt6a:
        push    de
        push    hl
        ld      hl,(nb0)
        ld      bc,(nbl)
        add     hl,bc
        ld      de,(nb0+2)
        jr      nc,nt6b
        inc     de
nt6b:
        push    de
        push    hl
        ld      hl,0Ah
        push    hl
        call    _st_findb
        pop     bc
        pop     bc
        pop     bc
        pop     bc
        pop     bc
        ld      bc,(nb0)
        or      a
        sbc     hl,bc
        inc     hl
        ld      (no),hl
        ld      hl,(nc)
        dec     hl
        ld      (nc),hl
        ld      a,h
        or      l
        jr      nz,nt6
        ld      hl,(nat)
        ld      bc,(no)
        add     hl,bc
        ld      de,(nat+2)
        jr      nc,nt7
        inc     de
nt7:
        pop     ix
        ret
nt5:                                ; k -= c; at += blen
        ld      hl,(nk)
        ld      de,(nc)
        or      a
        sbc     hl,de
        ld      (nk),hl
        jr      nc,nt5a
        ld      hl,(nk+2)
        dec     hl
        ld      (nk+2),hl
nt5a:
        ld      hl,(nat)
        ld      de,(nbl)
        add     hl,de
        ld      (nat),hl
        jr      nc,nt5b
        ld      hl,(nat+2)
        inc     hl
        ld      (nat+2),hl
nt5b:
        ld      hl,(ni)
        inc     hl
        ld      (ni),hl
        jp      nt4
nt_zero:
        ld      hl,0
        ld      de,0
        pop     ix
        ret

; void insert_block(u16 at, u16 len): a new logical block at index at (physical block taken from the free ones, bph[nb])
_insert_block:
        push    ix
        ld      ix,0
        add     ix,sp
        ld      hl,(_nb)
        ld      de,_bph
        add     hl,de
        ld      a,(hl)
        push    af                  ; the free physical block
        ld      hl,(_nb)
        ld      e,(ix+6)
        ld      d,(ix+7)
        or      a
        sbc     hl,de
        ld      b,h
        ld      c,l                 ; BC = nb - at
        ld      a,b
        or      c
        jr      z,ib2
        push    bc
        ld      hl,(_nb)            ; bph: LDDR up by one byte
        ld      de,_bph
        add     hl,de
        ld      d,h
        ld      e,l
        dec     hl
        lddr
        pop     bc
        push    bc
        ld      hl,(_nb)            ; bnl
        ld      de,_bnl
        add     hl,de
        ld      d,h
        ld      e,l
        dec     hl
        lddr
        pop     bc
        sla     c                   ; blen: 2 bytes per entry, up by two bytes
        rl      b
        ld      hl,(_nb)
        add     hl,hl
        ld      de,_blen
        add     hl,de
        dec     hl                  ; last byte of blen[nb-1]
        ld      d,h
        ld      e,l
        inc     de
        inc     de
        lddr
ib2:
        ld      l,(ix+6)
        ld      h,(ix+7)
        push    hl
        ld      de,_bph
        add     hl,de
        pop     de
        pop     af
        ld      (hl),a              ; bph[at] = free physical block
        ex      de,hl
        push    hl
        ld      de,_bnl
        add     hl,de
        ld      (hl),0FFh           ; bnl[at] = unknown
        pop     hl
        add     hl,hl
        ld      de,_blen
        add     hl,de
        ld      e,(ix+4)
        ld      d,(ix+5)
        ld      (hl),e
        inc     hl
        ld      (hl),d              ; blen[at] = len
        ld      hl,(_nb)
        inc     hl
        ld      (_nb),hl
        pop     ix
        ret

; void remove_block(u16 at): drop logical block at; its physical block becomes the last free one
_remove_block:
        push    ix
        ld      ix,0
        add     ix,sp
        ld      l,(ix+4)
        ld      h,(ix+5)
        ld      de,_bph
        add     hl,de
        ld      a,(hl)
        push    af                  ; physical block being freed
        ld      hl,(_nb)
        ld      e,(ix+4)
        ld      d,(ix+5)
        or      a
        sbc     hl,de
        dec     hl
        ld      b,h
        ld      c,l                 ; BC = nb - at - 1
        ld      a,b
        or      c
        jr      z,rb2
        push    bc
        ld      l,(ix+4)
        ld      h,(ix+5)
        ld      de,_bph
        add     hl,de
        ld      d,h
        ld      e,l
        inc     hl
        ldir
        pop     bc
        push    bc
        ld      l,(ix+4)
        ld      h,(ix+5)
        ld      de,_bnl
        add     hl,de
        ld      d,h
        ld      e,l
        inc     hl
        ldir
        pop     bc
        sla     c
        rl      b
        ld      l,(ix+4)
        ld      h,(ix+5)
        add     hl,hl
        ld      de,_blen
        add     hl,de
        ld      d,h
        ld      e,l
        inc     hl
        inc     hl
        ldir
rb2:
        ld      hl,(_nb)
        dec     hl
        ld      de,_bph
        add     hl,de
        pop     af
        ld      (hl),a
        ld      hl,(_nb)
        dec     hl
        ld      (_nb),hl
        pop     ix
        ret

lp:     defs    4
le:     defs    4
bb:     defs    4
sp1:    defs    4
cn:     defs    4
so0:    defs    2
so1:    defs    2
tt:     defs    4
nk:     defs    4
nat:    defs    4
nb0:    defs    4
ni:     defs    2
nc:     defs    2
nbl:    defs    2
no:     defs    2
_blen:  defs    2*TX_NBMAX
_bnl:   defs    TX_NBMAX
_bph:   defs    TX_NBMAX
_nb:    defs    2
_ci:    defs    2
_cs:    defs    4
tx_NB:  defs    2
tx_total: defs  4
tx_hint: defb   0
ad_last: defs   2
ax_b:   defs    4
lc_h:   defb    0
rd_n:   defs    4                   ; (rd_n, rd_p, rd_dst: the stack image of tx_read)
rd_p:   defs    4
rd_dst: defs    2
rd_o:   defs    2
rd_k:   defs    2
mg_i:   defs    2
mg_a:   defs    2
mg_b:   defs    2
in_n:   defs    4                   ; (in_n, in_src, in_p: the stack image of tx_ins)
in_src: defs    2
in_p:   defs    4
in_off: defs    2
in_bl:  defs    2
in_tl:  defs    2
in_k:   defs    2
dl_n:   defs    4                   ; (dl_n, dl_p: the stack image of tx_del)
dl_p:   defs    4
