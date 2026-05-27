;
;	(TOS) += A
;	return original (TOS)
;
	.export __postincc

__postincc:
	ld	e,a
	ld	hl,sp+2
	ld	a,(hl)
	ld	h,(hl)
	ld	l,a
	ld	a,(hl)
	ld	d,a
	add	a,e
	ld	(hl),a
	ld	a,d
	pop	hl
	inc	sp
	inc	sp
	jp	(hl)

	