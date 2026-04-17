;
;	(TOS) &= BCHL
;
	.export __andeql

__andeql:
	call	__eqprep
	
	ld	a,(hl)
	and	e
	ldi	(hl),a
	ld	e,a
	ld	a,(hl)
	and	d
	ldi	(hl),a
	ld	d,a
	ld	a,(hl)
	and	c
	ldi	(hl),a
	ld	c,a
	ld	a,(hl)
	and	b
	ld	(hl),a
	ld	b,a

	ld	l,e
	ld	h,d

	pop	de
	add	sp,4
	push	de
	ret
