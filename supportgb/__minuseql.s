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
	add	sp,4
	push	de
	ret

	
	