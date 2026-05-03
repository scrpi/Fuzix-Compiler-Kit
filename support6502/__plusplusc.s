
;	General plusplus operation for 8bits. This one is used when
;	there are complex forms both sides. In this case the top of the
;	data stack is the pointer

	.export	__plusplusc
	.export	__plusplustmpc
	.export	__plusplustmpuc
	.code

__plusplusc:
	jsr	__poptmp	; pop TOS into @tmp, preserve XA
				; Y is set to 0 after this
	jmp	doop
__plusplustmpc:
__plusplustmpuc:
	stx	@tmp+1
	ldy	#0
doop:
	clc
	sta	@tmp1
	lda	(@tmp),y
	tax
	adc	@tmp1
	sta	(@tmp),y
	txa
	rts

