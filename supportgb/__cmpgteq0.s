;
;	DE >= 0
;
	.export __cmpgteq0

__cmpgteq0:
	bit	7,d
	ld	de,0
	jr	z, true
	xor	a
	ret
true:
	inc	e
	ret
