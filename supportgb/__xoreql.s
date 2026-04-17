;
;	(TOS) ^= BCHL
;
	.export __xoreql

__xoreql:
	call	__eqprep
	
	ld	a,(hl)
	xor	e
	ldi	(hl),a
	ld	e,a
	ld	a,(hl)
	xor	d
	ldi	(hl),a
	ld	d,a
	ld	a,(hl)
	xor	c
	ldi	(hl),a
	ld	c,a
	ld	a,(hl)
	xor	b
	ld	(hl),a
	ld	b,a

	ld	l,e
	ld	h,d

	pop	de
	inc	sp
	inc	sp
	push	de
	ret
