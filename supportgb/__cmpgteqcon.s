;
;	HL < DE signed
;
	.export __cmpgteqcon

__cmpgteqcon:
	ld	a,h
	xor	d
	cp	128
	jr	c,sign_same
	xor	d
	rlca
	jr	c,false
	jr	true

sign_same:
	cp	d
	jr	c,false
	jr	nz,true
	ld	a,l
	cp	e
	jr	c, false
true:	ld	hl,0
	inc	l
	ret
false:	xor	a
	ld	h,a
	ld	l,a
	ret

