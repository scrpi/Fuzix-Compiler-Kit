;
;	(TOS) < HL
;
	.export __cclteq
	.export __cmpgteq

__cclteq:
	ld	d,h
	ld	e,l
	ld	hl,sp+2
	call	__cmpgteq
	jp	__popint
__cmpgteq:
	inc	hl
	ldd	a,(hl)
	xor	d
	cp	128
	jr	c,sign_same
	xor	d
	; -ve is true +ve is false
	rlca
	jr	c,true
	jr	false
sign_same:
	; upper value is still in HL and DE
	cp	d
	jr	c,true
	jr	nz,false
	; Now compare the low half
	ld	a,(hl)
	cp	e
	jr	c, true
	jr	z, true
false:	xor	a
	ld	h,a
	ld	l,a
	ret
true:
	ld	hl,0
	inc	l
	ret
