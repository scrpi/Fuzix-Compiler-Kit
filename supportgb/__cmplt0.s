;
;	HL < 0
;
	.export __cmplt0

__cmplt0:
	bit	7,h
	ld	hl,0
	ret	z
	inc	l
	ret
