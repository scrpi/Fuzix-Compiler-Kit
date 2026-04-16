;
;	(TOS) < HL
;
	.export __ccgt
	.export __cmplt

__ccgt:
	ld	d,h
	ld	e,l
	ld	hl,sp+2
	call	__cmplt
	jp	__popint
__cmplt:
	inc	hl
	ldd	a,(hl)
	xor	d
	cp	128
	jr	c,sign_same
	xor	d
	; +ve is true -ve is false
	rlca
	jr	c,false
	jr	true

sign_same:
	; upper value is still in HL and DE
	cp	d
	jr	z,low
	jr	c,false
true:
	ld	hl,0
	inc	l
	ret
	; Now compare the low half
low:
	ld	a,(hl)
	cp	e
	jr	z, false
	jr	nc, true
false:	xor	a
	ld	h,a
	ld	l,a
	ret
