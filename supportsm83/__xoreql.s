;
;	(TOS) ^= BCDE
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

	pop	hl
	inc	sp
	inc	sp
	jp	(hl)
