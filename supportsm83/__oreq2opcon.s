;
;	(DE) & HL
;
	.export __oreq2opcon

__oreq2opcon:
	ld 	a,(de)
	or	l
	ld	(de),a
	inc	de
	ld	l,a
	ld	a,(de)
	or	h
	ld	(de),a
	ld	d,a
	ld	e,l
	ret

