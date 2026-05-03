;
;	General plusplus operation for 16bits. This one is used when
;	there are complex forms both sides. In this case the top of the
;	data stack is the pointer

	.export	__plusplus
	.export	__plusplustmp
	.export	__plusplustmpu
	.code

__plusplus:
	jsr	__poptmp	; pop TOS into @tmp, preserve XA
				; Y is set to 0 after this
__plusplustmp:
__plusplustmpu:
	ldy	#0
	sta	@tmp1
	stx	@tmp1+1
	clc
	lda	(@tmp),y
	pha
	adc	@tmp1
	sta	(@tmp),y
	iny
	lda	(@tmp),y
	tax
	adc	@tmp1+1
	sta	(@tmp),y
	pla
	rts

