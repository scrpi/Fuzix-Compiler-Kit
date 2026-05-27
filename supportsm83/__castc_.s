;
;	Signed char in L to integer in HL
;
	.export __castc_
;
;	Worth inlining ? TODO
;
__castc_:
	ld	d,0
	ld	e,a
	bit	7,e
	ret	z
	dec	d
	ret
