;
;	(HL) |= DE
;	Return result
;
	.export __xoreq2op

__xoreq2op:
	ld	a,(hl)
	xor	e
	ld	e,a
	ldi	(hl),a
	ld	a,(hl)
	xor	d
	ld	(hl),a
	ld	h,a
	ld	l,e
	ret
