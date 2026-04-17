;
;	(TOS) + BCHL
;
	.export __minusl

__minusl:
	call	__eqprep
	; now (HL) + BCDE
	ldi	a,(hl)
	sub	e
	ld	e,a
	ldi	a,(hl)
	sbc	d
	ld	d,a
	ldi	a,(hl)
	sbc	c
	ld	c,a
	ld	a,(hl)
	sbc	b
	ld	b,a
	ld	l,e
	ld	h,d
	pop	de
	add	sp,4
	push	de
	ret
