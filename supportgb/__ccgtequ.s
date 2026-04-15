;
;	(TOS) >= HL
;
	.export __ccgtequ
	.export __cmpgtequ

__ccgtequ:
	ld	d,h
	ld	e,l
	ld	hl,sp+3
	call	__cmpgtequ
	jp	__popint
__cmpgtequ:
	ldd	a,(hl)
	cp	d
	jr	c, true
	jr	nz, false
	ld	a,(hl)
	cp	e
	jr	c, false
true:	ld	hl,0
	inc	l		; clear Z
	ret
false:
	xor	a		; set Z
	ld	h,a
	ld	l,a
	ret
