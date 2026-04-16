;
;	(HL) &= DE
;	Return result
;
	.export __andeq2op

__andeq2op:
	ld	a,(hl)
	and	e
	ld	e,a
	ldi	(hl),a
	ld	a,(hl)
	and	d
	ld	(hl),a
	ld	h,a
	ld	l,e
	ret
