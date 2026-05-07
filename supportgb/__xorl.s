;
;	BCHL ^ TOS
;
	.export __xorl

__xorl:
	ld	hl,sp+2
	ldi	a,(hl)
	xor	e
	ld	e,a
	ldi	a,(hl)
	xor	d
	ld	d,a
	ldi	a,(hl)
	xor	c
	ld	c,a
	ldi	a,(hl)
	xor	b
	ld	b,a
	pop	hl
	add	sp,4
	jp	(hl)
