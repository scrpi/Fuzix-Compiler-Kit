;
;	TOS + BCDE
;
	.export __minusl

__minusl:
	ld	hl,sp+2
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
	pop	hl
	add	sp,4
	jp	(hl)
