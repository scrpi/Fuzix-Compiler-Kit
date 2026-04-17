	.export __cast_l
	.export __castc_l


__castc_l:
	bit	7,l
	ld	h,0
	jr	z,__cast_l
	dec	h
__cast_l:
	bit	7,h
	ld	bc,0
	ret	z
	dec	bc
	ret
