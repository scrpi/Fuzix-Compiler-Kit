	; TOS != HL
	.export __cceq

__cceq:
	ld	hl,sp+3
	ldd	a,(hl)
	cp	h
	jr	nz,false
	ld	a,(hl)
	cp	l
	jr	nz, false
true:
	ld	hl,0
	inc	l
out:
	pop	de
	inc	sp
	inc	sp
	push	de
	ret
false:
	xor	a
	ld	l,a
	ld	h,a
	jr	out
