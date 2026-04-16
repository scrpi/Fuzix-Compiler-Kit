	; TOS != HL
	.export __ccne

__ccne:
	ld	hl,sp+3
	ldd	a,(hl)
	cp	h
	jr	nz,false
	ld	a,(hl)
	cp	l
	jr	z, true
false:
	xor	a
	ld	h,a
	ld	l,a
	ret
true:
	ld	hl,0
	inc	l
	ret

