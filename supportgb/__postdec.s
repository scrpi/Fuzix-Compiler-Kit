;
;	(TOS) -= HL
;	return original (TOS)
;
	.export __postdec

__postdec:
	; Much messier as we have to do things in the right order
	; and the SM83 doesn't quite have enough registers for the modes
	; available
	ld	b,d
	ld	c,e
	ld	hl,sp+2
	ldi	a,(hl)
	ld	h,(hl)
	ld	l,a
	;	HL is the pointer
	;	BC is the value to subtract
	ld	a,(hl)
	ld	e,a
	sub	a,c
	ldi	(hl),a
	ld	a,(hl)
	ld	d,a
	sbc	a, b
	ld	(hl),a
	pop	hl
	inc	sp
	inc	sp
	jp	(hl)
	