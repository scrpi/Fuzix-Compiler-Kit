;
;	BCDE | TOS
;
	.export __orl

__orl:
	ld	hl,sp+2
	ldi	a,(hl)
	or	e
	ld	e,a
	ldi	a,(hl)
	or	d
	ld	d,a
	ldi	a,(hl)
	or	c
	ld	c,a
	ldi	a,(hl)
	or	b
	ld	b,a
	pop	hl
	add	sp,4
	jp	(hl)
