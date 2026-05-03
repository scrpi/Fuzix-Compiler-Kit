;
;	Pop a 16bit value from stack into XA
;
;	Based on code by Ullrich von Bassetwitz for CC65
;	Always returns with Y = 0
;
	.export __pop
	.code

__pop:
	ldy	#1
	lda	(@sp),y
	tax
	dey
	lda	(@sp),y
	jmp	__incsp2
