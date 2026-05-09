;
;	General plusplus operation for 16bits. This one is used when
;	there are complex forms both sides. In this case the top of the
;	data stack is the pointer

	.export	__postinc
	.export	__plusplustmp
	.export	__plusplustmpu
	.export	__plusplusy
	.export	__plusplus1
	.export	__plusplus2
	.export	__plusplus4
	.export	__l_plusplus
	.export	__l_plusplus1
	.export	__l_plusplus2
	.export	__l_plusplus3
	.export	__l_plusplus4
	.code

__postinc:
	jsr	__poptmp	; pop TOS into @tmp, preserve XA
				; Y is set to 0 after this
__plusplustmp:
__plusplustmpu:
	sta	@tmp1
	stx	@tmp1+1
	ldy	#0
do_pp:
	lda	(@tmp),y
	pha
	clc
	adc	@tmp1
	sta	(@tmp),y
	iny
	lda	(@tmp),y
	tax
	adc	@tmp1+1
	sta	(@tmp),y
	pla
	rts

__plusplus1:
	ldy	#1
__plusplusy:
	sty	@tmp1
	ldy	#0
	sty	@tmp1+1
	sta	@tmp
	stx	@tmp+1
	jmp	do_pp
__plusplus2:
	ldy	#2
	bne	__plusplusy
__plusplus4:
	ldy	#4
	bne	__plusplusy

__l_plusplus4:
	lda	#4
	bne	__l_plusplusa
__l_plusplus3:
	lda	#3
	bne	__l_plusplusa
__l_plusplus2:
	lda	#2
	bne	__l_plusplusa
__l_plusplus1:
	lda	#1
__l_plusplusa:
	ldx	#0
__l_plusplus:
	sta	@tmp1
	stx	@tmp1+1
	tya
	clc
	adc	@sp
	sta	@tmp
	lda	@sp+1
	adc	#0
	sta	@tmp+1
	ldy	#0
	beq	do_pp
