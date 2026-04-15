;
;	(TOS) < HL
;
	.export __ccltu
	.export __cmpltu

__ccltu:
	ld	d,h
	ld	e,l
	ld	hl,sp+3
	call	__cmplt
	jp	__popint
__cmpltu:
	ldd	a,(hl)
	cp	d
	jr	c, true
	jr	nz, false
	ld	a,(hl)
	cp	e
	jr	c, true
false:	xor	a
	ld	h,a
	ld	l,a
	ret
true:
	ld	hl,0
	inc	l
	ret

	

	