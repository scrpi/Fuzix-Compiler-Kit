;
;	HL >= DE
;
	.export __cmpgteqconu

__cmpgteqconu:
	ld 	a,h
	cp	d
	jr	c, false
	jr	nz, true
	ld	a,l
	cp	e
	jr	nc, true
false:	xor	a
	ld	h,a
	ld	l,a
	ret
true:
	ld	hl,0
	inc	l
	ret
