;
;	Pop a 32hit value from stack into tmp1/tmp, preserve XA. Leaves Y as 0
;
;	Based on code by Ullrich von Bassetwitz for CC65
;
	.export __pop32
	.export __incsp4
	.code

__pop32:
	pha
	ldy	#3
	lda	(@sp),y
	sta	@tmp1+1
	dey
	lda	(@sp),y
	sta	@tmp1
	dey
	lda	(@sp),y
	sta	@tmp+1
	dey
	lda	(@sp),y
	sta	@tmp
__incsp4:
	lda	#4
	clc
	adc	@sp
	sta	@sp
	bcc	noinc
	inc	@sp+1
noinc:	pla
	rts
