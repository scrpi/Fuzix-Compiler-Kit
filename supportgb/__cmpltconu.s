;
;	HL < DE
;
	.export __cmpltconu

__cmpltconu:
	ld 	a,h
	cp	d
	jr	c, true
	jr	nz, false
	ld	a,l
	cp	e
	jr	nc, false
true:
	ld	hl,0
	inc	l
	ret
false:	xor	a
	ld	h,a
	ld	l,a
	ret
