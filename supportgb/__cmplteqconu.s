	.export __cmplteqconu
	.export __cmpltequ
	.export	__ccgtequ

;	TOS >= DE
__ccgtequ:
	pop	bc
	pop	hl
	push	bc
	jr	__cmplteqconu

;	DE <= (HL)
__cmpltequ:
	ldi	a,(hl)
	ld	h,(hl)
	ld	l,a	

;	DE <= HL
__cmplteqconu:
	ld 	a,h
	cp	d
	jr	c, false
	jr	nz, true
	ld	a,l
	cp	e
	jr	nc, true
false:	xor	a
	ld	d,a
	ld	e,a
	ret
true:
	ld	de,0
	inc	e
	ret
