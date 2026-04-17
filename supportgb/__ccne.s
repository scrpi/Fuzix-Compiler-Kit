	.export __ccne
	.export __cmpne

;	TOS != HL
__ccne:
	ld	e,l
	ld	d,h
	ld	hl,sp+2
	call	__cmpne
	pop	de
	inc	sp
	inc	sp
	push	de
	ret

;	(HL) != DE
__cmpne:
	ldi	a,(hl)
	cp	e
	jr	nz,true
	ld	a,(hl)
	cp	d
	jr	nz, true
false:
	xor	a
	ld	h,a
	ld	l,a
	ret
true:
	ld	hl,0
	inc	l
	ret


