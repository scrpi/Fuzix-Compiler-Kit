;
;	(TOS) += BCDE
;
;	return original TOS
;
	.export __postincl

__postincl:
	ld	hl,sp+2
	ldi	a,(hl)
	ld	h,(hl)
	ld	l,a
	ld	a,(hl)
	push	af		; no room otherwise
	add	e
	ldi	(hl),a
	ld	a,(hl)
	ld	e,a
	adc	d
	ldi	(hl),a
	ld	a,(hl)
	ld	d,a
	adc	c
	ldi	(hl),a
	ld	a,(hl)
	ld	c,a
	adc	b
	ld	(hl),a
	; Sort out saved bits
	ld	b,c
	ld	c,d
	ld	d,e
	pop	af
	ld	e,a
	; Now clean up
	pop	hl
	inc	sp
	inc	sp
	jp	(hl)
	
	