;
;	(HL) ^ DE
;
	.export __xoreq2opcon

__xoreq2opcon:
	ld 	a,(hl)
	xor	e
	ldi	(hl),a
	ld	e,a
	ld	a,(hl)
	xor	d
	ld	(hl),a
	ld	h,a
	ld	l,e
	ret

