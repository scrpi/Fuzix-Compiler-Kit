;
;	BCHL | TOS
;
	.export __orl

__orl:
	ld	e,l
	ld	d,h
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
	ld	h,d
	ld	l,e
	pop	de
	add	sp,4
	push	de
	ret
