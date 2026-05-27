;
;	16bit signed comparisons
;
	.export __ccgt
	.export __cmplt
	.export __cmpltcon

;	TOS > DE
__ccgt:
	pop	bc
	pop	hl		; args reverse so this is gt not lt
	push	bc
	jr	__cmpltconu
;	DE < (HL)
__cmplt:
	ldi	a,(hl)
	ld	h,(hl)
	ld	l,a	

__cmpltcon:
	ld	a,d
	xor	h
	cp	128
	jr	c,sign_same
	xor	h
	rlca
	jr	c,true
	jr	false
sign_same:
	xor	h
	cp	h
	jr	c,true
	jr	nz,false
	ld	a,e
	cp	l
	jr	c, true
false:	xor	a
	ld	d,a
	ld	e,a
	ret
true:	ld	de,0
	inc	e
	ret
