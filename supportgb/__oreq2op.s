;
;	(HL) |= DE
;	Return result
;
	.export __oreq2op

__oreq2op:
	ld	a,(hl)
	or	e
	ld	e,a
	ldi	(hl),a
	ld	a,(hl)
	or	d
	ld	(hl),a
	ld	h,a
	ld	l,e
	ret
