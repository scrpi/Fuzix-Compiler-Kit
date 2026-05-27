;
;	16bit signed comparisons
;
	.export __cclteq
	.export __cmpgteq
	.export __cmpgteqcon
;	TOS >= DE
__cclteq:
	pop	bc
	pop	hl		; args reverse so this is gt not lt
	push	bc
	jr	__cmplteqcon
;	DE <= (HL)
__cmpgteq:
	ldi	a,(hl)
	ld	h,(hl)
	ld	l,a	
;	DE <= HL
__cmpgteqcon:
	ld	a,d
	xor	h
	cp	128
	jr	c,sign_same
	xor	h
	rlca
	jr	c,false
	jr	true
sign_same:
	xor	h
	cp	h
	jr	c,false
	jr	nz,true
	ld	a,e
	cp	l
	jr	c, false
true:	ld	de,0
	inc	e
	ret
false:	xor	a
	ld	d,a
	ld	e,a
	ret

