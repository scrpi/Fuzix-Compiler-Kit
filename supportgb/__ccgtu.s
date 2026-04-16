;
;	(TOS) > HL
;
	.export __ccgtu
	.export	__cmpltu

__ccgtu:
	ld	d,h
	ld	e,l
	ld	hl,sp+2
	call	__cmpltu
	jp	__popint
__cmpltu:
	;	DE < (HL)
	inc	hl
	ldd	a,(hl)
	cp	d
	jr	c, false
	jr	nz, true
	ld	a,(hl)
	cp	e
	jr	c, false
	jr	z, false
true:	ld	hl,0
	inc	l		; clear Z
	ret
false:
	xor	a		; set Z
	ld	h,a
	ld	l,a
	ret
