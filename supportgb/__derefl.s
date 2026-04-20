;
;	BCHL = (HL)
;
	.export __dereff
	.export __derefl

__derefl:
__dereff:
	ldi	a,(hl)
	ld	e,a
	ldi	a,(hl)
	ld	d,a
	ldi	a,(hl)
	ld	b,(hl)
	ld	c,a
	ld	h,d
	ld	l,e
	ret

