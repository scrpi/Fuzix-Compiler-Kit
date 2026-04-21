;
;	boolify BCHL
;
	.export __booll
	.export __notl

__booll:
	ld	a,b
	or	c
	or	h
	or	l
	jr	z, false
true:
	ld	hl,0
	inc	l
	ret
false:
	xor	a
	ld	h,a
	ld	l,a
	ret

__notl:
	ld	a,b
	or	c
	or	h
	or	l
	jr	z, true
	jr	false

