;
;	(DE) -= HL
;	return result
;
	.export __minuseq2opcon

__minuseq2opcon:
	ld	a,(de)
	sub	l
	ld	(de),a
	inc	de
	ld	l,a
	ld	a,(de)
	sbc	h
	ld	(de),a
	ld	e,l
	ld	d,a
	ret
