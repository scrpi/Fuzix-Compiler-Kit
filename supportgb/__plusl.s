;
;	TOS + BCDE
;
	.export __plusl

__plusl:
	ld	hl,sp+2
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
	pop	hl
	add	sp,4
	jp	(hl)
