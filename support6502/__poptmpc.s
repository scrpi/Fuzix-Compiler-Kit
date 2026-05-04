;
;	Pop an 8bit value from stack into tmp, preserve XA. Leaves Y as 0
;
;	Based on code by Ullrich von Bassetwitz for CC65
;
	.export __poptmpc
	.export __incsp
	.export __add1sp
	.code

__poptmpc:
	pha
	ldy	#0
	lda	(@sp),y
	sta	@tmp
	pla
__add1sp:
__incsp:
	inc	@sp
	bne	l1
	inc	@sp+1
l1:	rts
