;
;	HL >= 0
;
	.export __cmpgteq0

__cmpgteq0:
	bit	7,h
	ld	hl,0
	jr	z, true
	xor	a
	ret
true:
	inc	l
	ret
