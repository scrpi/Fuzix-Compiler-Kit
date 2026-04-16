;
;	(TOS) -= A
;	return original (TOS)
;
	.export __postdecc

__postdecc:
	ld	e,a
	ld	hl,sp+2
	ldi	a,(hl)
	ld	h,(hl)
	ld	l,a
	;	HL is the pointer
	ld	a,(hl)
	ld	d,a
	sub	e
	ld	(hl),a
	ld	a,d
	pop	hl
	inc	sp
	inc	sp
	jp	(hl)
