; marks_z80.asm - keep the marks a-z in step with an edit.
;   void madj(pos_t p, pos_t n, u8 ins)   (pos_t = 32 bit, mk[26] is the editor's mark table, FFFFFFFFh = unset)
;   ins: a mark at >= p moves up by n.   del: a mark at >= p+n moves down by n, one inside the deleted text goes to p.
    SECTION code_user
    PUBLIC _madj
    EXTERN _mk

; carry set if (HL) < (DE) as 32 bit; keeps HL, DE
m_cmp:
    push hl
    push de
    or a
    ld b,4
mc1:
    ld a,(hl)
    ex de,hl
    sbc a,(hl)
    ex de,hl
    inc hl
    inc de
    djnz mc1
    pop de
    pop hl
    ret

; (HL) += (DE)
m_add:
    push hl
    push de
    or a
    ld b,4
ma1:
    ld a,(de)
    adc a,(hl)
    ld (hl),a
    inc hl
    inc de
    djnz ma1
    pop de
    pop hl
    ret

; (HL) -= (DE)
m_sub:
    push hl
    push de
    or a
    ld b,4
ms1:
    ld a,(hl)
    ex de,hl
    sbc a,(hl)
    ex de,hl
    ld (hl),a
    inc hl
    inc de
    djnz ms1
    pop de
    pop hl
    ret

_madj:
    push ix
    ld ix,0
    add ix,sp                  ; +4 ins, +6 n (4), +10 p (4)
    push ix
    pop hl
    ld de,6
    add hl,de
    ld de,m_n
    ld bc,8
    ldir                       ; m_n, m_p
    ld hl,m_p
    ld de,m_pe
    ld bc,4
    ldir
    ld hl,m_pe
    ld de,m_n
    call m_add                 ; m_pe = p + n
    ld a,(ix+4)
    ld (m_ins),a
    ld hl,_mk
    ld a,27
mj_l:
    ld (m_cnt),a
    ld a,(hl)                  ; unset mark?
    inc hl
    and (hl)
    inc hl
    and (hl)
    inc hl
    and (hl)
    dec hl
    dec hl
    dec hl
    inc a
    jr z,mj_nx
    ld a,(m_ins)
    or a
    jr z,mj_del
    ld de,m_p
    call m_cmp
    jr c,mj_nx
    ld de,m_n
    call m_add
    jr mj_nx
mj_del:
    ld de,m_pe
    call m_cmp
    jr c,mj_in
    ld de,m_n
    call m_sub
    jr mj_nx
mj_in:                         ; m < p+n : if p < m the mark moves to p
    ex de,hl                   ; de = m
    ld hl,m_p
    call m_cmp                 ; carry if p < m
    ex de,hl                   ; hl = m
    jr nc,mj_nx
    ex de,hl
    ld hl,m_p
    ld bc,4
    push de
    ldir
    pop hl
mj_nx:
    ld de,4
    add hl,de
    ld a,(m_cnt)
    dec a
    jr nz,mj_l
    pop ix
    ret

    SECTION bss_user
m_n:    defs 4
m_p:    defs 4
m_pe:   defs 4
m_ins:  defb 0
m_cnt:  defb 0
