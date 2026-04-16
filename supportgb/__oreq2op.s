;
;	(DE) &= (HL)
;	Return result
;
	.export __oreq2op

__oreq2op:
	ld	a,(de)
	or	(hl)
	ld	(de),a
	inc	hl
	inc	de
	push	af
	ld	a,(de)
	or	(hl)
	ld	(de),a
	ld	h,a
	pop	af
	ld	l,a
	ret
