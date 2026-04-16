;
;	(TOS) += HL
;	return original (TOS)
;
	.export __postinc

__postinc:
	ld	d,h
	ld	e,l
	ld	hl,sp+2
	ldi	a,(hl)
	ld	h,(hl)
	ld	l,a
	ld	a,e		; oh for another register
	add	a,(hl)		; a is now the result but (hl) is the old
	ld	e,(hl)		; save old as we don't need E any more
	ldi	(hl),a
	ld	a,d
	adc	a,(hl)
	ld	d,(hl)
	ld	(hl),a
	ld	h,d
	ld	l,e
	pop	de
	inc	sp
	inc	sp
	push	de
	ret

	