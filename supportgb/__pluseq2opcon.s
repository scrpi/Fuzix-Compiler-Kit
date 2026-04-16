;
;	(HL) += DE
;	return result
;
	.export __pluseq2opcon

__pluseq2opcon:
	ld	a,(hl)
	add	e
	ldi	(hl),a
	ld	l,a
	ld	a,(hl)
	adc	d
	ld	(hl),a
	ld	h,a
	ret
