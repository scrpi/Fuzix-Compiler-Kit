	.export __pluseq
	.export __pluseq2op
;
;	(TOS) -= DE
;
__pluseq:
	call	__eqprep
	; (HL) + DE
	ld	a,(hl)
	add	e
	ldi	(hl),a
	ld	e,a
	ld	a,(hl)
	adc	d
	ld	(hl),a
	ld	d,a
	pop	hl
	inc	sp
	inc	sp
	jp	(hl)

	; (DE) += (HL)
__pluseq2op:
	ld	c,(hl)
	inc	hl
	ld	b,(hl)
	; (DE) += BC
	ld	l,e
	ld	h,d
	; (HL) += BC
	ld	a,(hl)
	add	c
	ldi	(hl),a
	ld	e,a
	ld	a,(hl)
	adc	b
	ld	(hl),a
	ld	d,a
	ret
