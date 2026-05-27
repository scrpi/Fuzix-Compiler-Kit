;
;	(DE) += HL
;	return result
;
;	FIXME: flip this one in the compiler ?
;
	.export __pluseq2opcon

__pluseq2opcon:
	ld	a,(de)
	add	l
	ld	(de),a
	inc	de
	ld	l,a
	ld	a,(de)
	adc	h
	ld	(de),a
	ld	d,a
	ld	e,l
	ret
