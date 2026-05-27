;
;	BCDE = (DE)
;
	.export __dereff
	.export __derefl

__derefl:
__dereff:
	ld	l,e
	ld	h,d
	ldi	a,(hl)
	ld	e,a
	ldi	a,(hl)
	ld	d,a
	ldi	a,(hl)
	ld	c,a
	ld	b,(hl)
	ret

