;
;	(DE) & HL
;
	.export __oreq2opcon

__oreq2opcon:
	ld 	a,(de)
	or	h
	ld	(de),a
	ld	h,a
	inc	de
	ld	a,(de)
	or	l
	ld	(de),a
	ld	l,a
	ret

