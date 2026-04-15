;
;	(TOS) <= HL
;
	.export __ccltequ
	.export __cmpltequ

__ccltequ:
	ld	d,h
	ld	e,l
	ld	hl,sp+2
	call	__cmpltequ
	; Should think if return in DE is saner ?
	jp	__popint
__cmpltequ:
	inc	hl
	ldd	a,(hl)
	cp	d
	jr	c, true
	jr	nz, false
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
