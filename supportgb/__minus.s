;
;	TOS - DE
;
	export	__minus

__minus:
	ld	hl,sp+2
	ldi	a,(hl)
	sub	e
	ld	e,a
	ld	a,(hl)
	sbc	d
	ld	d,a
	pop	hl
	inc	sp
	inc	sp
	jp	(hl)
