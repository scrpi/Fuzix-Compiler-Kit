;
;	(TOS) < HL
;
	.export __ccltu
	.export __cmpgtu

__ccltu:
	ld	d,h
	ld	e,l
	ld	hl,sp+2
	; now (HL) < DE
	call	__cmpgtu
	jp	__popint
__cmpgtu:
	; DE > (HL)
	inc	hl
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
