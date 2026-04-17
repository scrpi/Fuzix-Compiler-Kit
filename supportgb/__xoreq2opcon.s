;
;	(DE) ^ HL
;
	.export __xoreq2opcon

__xoreq2opcon:
	ld 	a,(de)
	xor	h
	ld	(de),a
	ld	h,a
	inc	de
	ld	a,(de)
	xor	l
	ld	(de),a
	ld	l,a
	ret

