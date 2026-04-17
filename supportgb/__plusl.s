;
;	(TOS) + BCHL
;
	.export __plusl

__plusl:
	call	__eqprep
	; now (HL) + BCDE
	ldi	a,(hl)
	add	e
	ld	e,a
	ldi	a,(hl)
	adc	d
	ld	d,a
	ldi	a,(hl)
	adc	c
	ld	c,a
	ld	a,(hl)
	adc	b
	ld	b,a
	ld	l,e
	ld	h,d
	pop	de
	add	sp,4
	push	de
	ret
