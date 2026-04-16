	; TOS != HL
	.export __cceq

__cceq:
	ld	hl,sp+3
	ldd	a,(hl)
	cp	h
	jr	nz,true
	ld	a,(hl)
	xor	l	; compare and end up with A = 0 if equal
	jr	z, false
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
	; At this point A is 0 and Z
	ld	l,a
	ld	h,a
	jr	out
