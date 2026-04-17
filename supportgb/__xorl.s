;
;	BCHL ^ TOS
;
	.export __xorl

__xorl:
	ld	e,l
	ld	d,h
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
	ld	h,d
	ld	l,e
	pop	de
	add	sp,4
	push	de
	ret
