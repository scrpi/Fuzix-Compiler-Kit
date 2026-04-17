;
;	(HL) & DE
;
	.export __oreq2opcon

__oreq2opcon:
	ld 	a,(hl)
	or	e
	ldi	(hl),a
	ld	e,a
	ld	a,(hl)
	or	d
	ld	(hl),a
	ld	h,a
	ld	l,e
	ret

