	.export __cast_l
	.export __cast_ul
	.export __castc_l


__castc_l:
	bit	7,e
	ld	d,0
	jr	z,__cast_l
	dec	d
__cast_ul:
__cast_l:
	bit	7,d
	ld	bc,0
	ret	z
	dec	bc
	ret
