;
;	(TOS) -= BCHL
;
;	return result
;
	.export __minuseql

__minuseql:
	ld	e,l
	ld	d,h
	ld	hl,sp+2
	ldi	a,(hl)
	ld	h,(hl)
	ld	l,a
	ld	a,(hl)
	sub	e
	ld	e,a
	ldi	(hl),a
	ld	a,(hl)
	sbc	d
	ld	d,a
	ldi	(hl),a
	ld	a,(hl)
	sbc	c
	ld	c,a
	ldi	(hl),a
	ld	a,(hl)
	sbc	b
	ld	b,a
	ld	(hl),a
	; Now clean up
	pop	de
	inc	sp
	inc	sp
	push	de
	ret

	
	