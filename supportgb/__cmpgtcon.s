;
;	16bit signed comparisons
;
	.export __cclt
	.export __cmpgt
	.export __cmpgtcon
;	TOS < DE
__cclt:
	pop	bc
	pop	hl		; args reverse so this is gt not lt
	push	bc
	jr	__cmpgtcon
;	DE > (HL)
__cmpgt:
	ldi	a,(hl)
	ld	h,(hl)
	ld	l,a	
;	DE > HL
__cmpgtcon:
	ld	a,h
	xor	d
	cp	128
	jr	c,sign_same
	xor	d
	rlca
	jr	c,true
	jr	false
sign_same:
	xor	d
	cp	d
	jr	c,true
	jr	nz,false
	ld	a,l
	cp	e
	jr	c, true
false:	xor	a
	ld	d,a
	ld	e,a
	ret
true:	ld	de,0
	inc	e
	ret
