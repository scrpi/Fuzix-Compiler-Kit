;
;	Helpers for shifts etc 32bit
;
	.export __shld32
	.export __shst32
	.export __pop32sh

__shld32:
	jsr	__poptmp
	; Y is now 0 and @tmp is the ptr, A was preserved
	pha
	lda	(@tmp),y
	sta	@tmp1
	iny
	lda	(@tmp),y
	sta	@tmp1+1
	iny
	lda	(@tmp),y
	sta	@tmp2
	iny
	lda	(@tmp),y
	sta	@tmp2+1
	; Value is loaded
	pla
	rts

__shst32:
	;	(@tmp) is valid still
	;	result is in @hireg X A
	;	Y was preserved so is 3
	pha
	lda	@hireg+1
	sta	(@tmp),y
	dey
	lda	@hireg
	sta	(@tmp),y
	dey
	txa
	sta	(@tmp),y
	dey
	pla
	sta	(@tmp),y
	rts

;
;	Pop a 32bit value into tmp2/tmp1.
;
__pop32sh:
	pha
	ldy	#3
	lda	(@sp),y
	sta	@tmp2+1
	dey
	lda	(@sp),y
	sta	@tmp2
	dey
	lda	(@sp),y
	sta	@tmp1+1
	dey
	lda	(@sp),y
	sta	@tmp1
__incsp2:
	lda	#4
	clc
	adc	@sp
	sta	@sp
	bcc	noinc
	inc	@sp+1
noinc:	pla
	rts
