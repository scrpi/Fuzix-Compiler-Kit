;
;	(TOS) ^= BCHL
;
	.export __oreql

__oreql:
	call	__eqprep
	
	ld	a,(hl)
	or	e
	ldi	(hl),a
	ld	e,a
	ld	a,(hl)
	or	d
	ldi	(hl),a
	ld	d,a
	ld	a,(hl)
	or	c
	ldi	(hl),a
	ld	c,a
	ld	a,(hl)
	or	b
	ld	(hl),a
	ld	b,a

	ld	l,e
	ld	h,d

	pop	de
	inc	sp
	inc	sp
	push	de
	ret
