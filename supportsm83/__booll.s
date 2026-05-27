;
;	boolify BCDE
;
	.export __booll
	.export __notl

__booll:
	ld	a,b
	or	c
	or	d
	or	e
	jr	z, false
true:
	ld	de,0
	inc	e
	ret
false:
	xor	a
	ld	d,a
	ld	e,a
	ret

__notl:
	ld	a,b
	or	c
	or	d
	or	e
	jr	z, true
	jr	false

