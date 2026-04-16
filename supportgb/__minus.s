;
;	TOS - HL
;
	export	__minus

__minus:
	ld	d,h
	ld	e,l
	ld	hl,sp+2
	ldi	a,(hl)
	sub	e
	ld	l,a
	ld	a,(hl)
	sbc	d
	ld	h,a
	pop	de
	inc	sp
	inc	sp
	push	de
	ret
