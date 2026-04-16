;
;	HL < DE signed
;
	.export __cmpltcon

__cmpltcon:
	ld	a,h
	xor	d
	cp	128
	jr	c,sign_same
	xor	d
	rlca
	jr	c,true
	jr	false

sign_same:
	cp	d
	jr	c,true
	jr	nz,false
	ld	a,l
	cp	e
	jr	c, true
false:	xor	a
	ld	h,a
	ld	l,a
	ret
true:	ld	hl,0
	inc	l
	ret

