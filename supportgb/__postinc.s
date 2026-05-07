;
;	(TOS) += DE
;	return original (TOS)
;
	.export __postinc

__postinc:
	ld	hl,sp+2
	ldi	a,(hl)
	ld	h,(hl)
	ld	l,a
	ld	a,e		; oh for another register
	ld	e,(hl)		; save old as we don't need E any more
	add	a,(hl)		; a is now the result but (hl) is the old
	ldi	(hl),a
	ld	a,d
	ld	d,(hl)
	adc	a,(hl)
	ld	(hl),a
	pop	hl
	inc	sp
	inc	sp
	jp	(hl)

	