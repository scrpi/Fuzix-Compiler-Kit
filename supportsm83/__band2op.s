;
;	(HL) & DE
;
	.export __band2op
	.export __band

__band:
	ld	hl,sp+2
	call	__band2op
	pop	hl
	pop	af
	jp	(hl)

__band2op:
	ldi	a,(hl)
	and	e
	ld	e,a
	ld	a,(hl)
	and	d
	ld	d,a
	ret
