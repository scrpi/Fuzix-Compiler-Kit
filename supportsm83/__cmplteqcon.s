;
;	16bit signed comparisons
;
	.export __ccgteq
	.export __cmplteq
	.export __cmplteqcon
;	TOS >= DE
__ccgteq:
	pop	bc
	pop	hl		; args reverse so this is gt not lt
	push	bc
	jr	__cmplteqcon
;	DE <= (HL)
__cmplteq:
	ldi	a,(hl)
	ld	h,(hl)
	ld	l,a	
;	DE <= HL
__cmplteqcon:
	ld	a,h
	xor	d
	cp	128
	jr	c,sign_same
	xor	d
	rlca
	jr	c,false
	jr	true
sign_same:
	xor	d
	cp	d
	jr	c,false
	jr	nz,true
	ld	a,l
	cp	e
	jr	c, false
true:	ld	de,0
	inc	e
	ret
false:	xor	a
	ld	d,a
	ld	e,a
	ret

