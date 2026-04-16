;
;	(TOS) <= HL
;
	.export __ccltequ
	.export __cmpgtequ

__ccltequ:
	ld	d,h
	ld	e,l
	ld	hl,sp+2
	; now (HL) <= DE
	call	__cmpgtequ
	; Should think if return in DE is saner ?
	jp	__popint
__cmpgtequ:
	; DE >= (HL)
	inc	hl
	ldd	a,(hl)
	cp	d
	jr	c, true
	jr	nz, false
	ld	a,(hl)
	cp	e
	jr	c, true
	jr	nz, false
true:
	ld	hl,0
	inc	l
	ret
false:	xor	a
	ld	h,a
	ld	l,a
	ret
