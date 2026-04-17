;
;	(HL) += DE
;	return result
;
	.export __pluseq2opcon

__pluseq2opcon:
	ld	a,(hl)
	add	e
	ldi	(hl),a
	ld	e,a
	ld	a,(hl)
	adc	d
	ld	(hl),a
	ld	h,a
	ld	l,e
	ret
