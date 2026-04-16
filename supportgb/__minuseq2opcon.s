;
;	(HL) -= DE
;	return result
;
	.export __minuseq2opcon

__minuseq2opcon:
	ld	a,(hl)
	sub	e
	ldi	(hl),a
	ld	l,a
	ld	a,(hl)
	sbc	d
	ld	(hl),a
	ld	h,a
	ret
