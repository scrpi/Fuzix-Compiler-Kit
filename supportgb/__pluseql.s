;
;	(TOS) += BCHL
;
;	return result
;
	.export __pluseql

__pluseql:
	ld	e,l
	ld	d,h
	ld	hl,sp+2
	ldi	a,(hl)
	ld	h,(hl)
	ld	l,a
	ld	a,(hl)
	add	e
	ld	e,a
	ldi	(hl),a
	ld	a,(hl)
	adc	d
	ld	d,a
	ldi	(hl),a
	ld	a,(hl)
	adc	c
	ld	c,a
	ldi	(hl),a
	ld	a,(hl)
	adc	b
	ld	b,a
	ld	(hl),a
	; Now clean up
	pop	de
	inc	sp
	inc	sp
	push	de
	ret

	
	