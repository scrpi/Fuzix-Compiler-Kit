	.export __plusl

;
;	TOS + hireg:XA. Used when there's a 32bit operation
;	that we don't inline the maths for
;
__plusl:
	ldy	#0
	clc
	adc	(@sp),y
	iny
	pha		; recovered in __incsp4
	txa
	adc	(@sp),y
	tax
	iny
	lda	@hireg
	adc	(@sp),y
	sta	@hireg
	iny
	lda	@hireg+1
	adc	(@sp),y
	sta	@hireg+1
	; This will fix the stack and pla
	jmp	__incsp4
