;
;	(DE) &= (HL)
;	Return result
;
	.export __andeq2op

__andeq2op:
	ld	a,(de)
	and	(hl)
	ld	(de),a
	inc	hl
	inc	de
	push	af
	ld	a,(de)
	and	(hl)
	ld	(de),a
	ld	d,a
	pop	af
	ld	e,a
	ret
