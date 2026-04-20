	.export __minuseq
	.export __minuseq2op
;
;	(TOS) -= HL
;
__minuseq:
	call	__eqprep
	; (HL) - DE
	ld	a,(hl)
	sub	e
	ldi	(hl),a
	ld	e,a
	ld	a,(hl)
	sbc	d
	ld	(hl),a
	ld	h,a
	ld	l,e
	pop	de
	inc	sp
	inc	sp
	push	de
	ret

__minuseq2op:
	; (DE) -= (HL)
	ldi	a,(hl)
	ld	h,(hl)
	ld	l,a
	; (DE) - HL
	push	de	; untangle this when we switch to
	push	hl	; DE as working: TODO
	pop	de
	pop	hl
	; (HL) - DE
	ld	a,(hl)
	sub	e
	ldi	(hl),a
	ld	e,a
	ld	a,(hl)
	sbc	d
	ld	(hl),a
	ld	h,a
	ld	l,e
	ret
