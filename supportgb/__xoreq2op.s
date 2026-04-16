;
;	(DE) &= (HL)
;	Return result
;
	.export __xoreq2op

__xoreq2op:
	ld	a,(de)
	xor	(hl)
	ld	(de),a
	inc	hl
	inc	de
	push	af
	ld	a,(de)
	xor	(hl)
	ld	(de),a
	ld	h,a
	pop	af
	ld	l,a
	ret
