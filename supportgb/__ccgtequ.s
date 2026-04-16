;
;	(TOS) >= HL
;
	.export __ccgtequ
	.export __cmpltequ

__ccgtequ:
	ld	d,h
	ld	e,l
	ld	hl,sp+2
	;	now (HL) >= DE
	call	__cmpltequ
	jp	__popint
__cmpltequ:
	; DE <= (HL)
	inc	hl
	ldd	a,(hl)
	cp	d
	jr	c, true
	jr	nz, false
	ld	a,(hl)
	cp	e
	jr	c, true
false:
	ld	hl,0
	inc	l
	ret
true:	xor	a
	ld	h,a
	ld	l,a
	ret
