;
;	(HL) & DE
;
	.export __band2op

__band2op:
	ldi	a,(hl)
	and	e
	ld	e,a
	ld	a,(hl)
	and	d
	ld	h,a
	ld	l,e
	ret
