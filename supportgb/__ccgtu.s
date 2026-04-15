;
;	(TOS) > HL
;
	.export __ccgtu
	.export	__cmpgtu

__ccgtu:
	ld	d,h
	ld	e,l
	ld	hl,sp+2
	call	__cmpgtu
	jp	__popint

__cmpgtu:
	inc	hl
	ldd	a,(hl)
	cp	d
	jr	c, false
	jr	nz, true
	ld	a,(hl)
	cp	e
	jr	c, false
	jr	z, false
true:	xor	a
	ld	h,a
	ld	l,a
	ret
false:
	ld	hl,0
	inc	l
	ret

	

	