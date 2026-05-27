;
;	DE < 0
;
	.export __cmplt0

__cmplt0:
	bit	7,d
	ld	de,0
	ret	z
	inc	e
	ret
