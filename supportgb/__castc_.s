;
;	Signed char in L to integer in HL
;
	.export __castc_
;
;	Worth inlining ? TODO
;
__castc_:
	ld	h,0
	bit	7,l
	ret	z
	dec	h
	ret
