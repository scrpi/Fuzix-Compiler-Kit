;
;	Unsigned 16x16 mul
;
	.export __mulc
	.export __muluc
	.export __multmpc
	.export __multmpuc
	.export __muleqc
	.export __mulequc
	.export __l_mulc

__l_mulc:
	jsr	__ytmpc
	jmp	__multmpc
__mulc:
__muluc:
	jsr	__poptmpc
__multmpc:
__multmpuc:
	; A * tmp
	sta	@tmp+1
	ldx	#8
	lda	#0
	lsr	@tmp
loop:	bcc	next
	clc
	adc	@tmp+1
next:
	ror	a
	ror	@tmp
	dex
	bne	loop
;
;	A is now the high bits, @tmp the low
;
	tax
	lda	@tmp
	rts

__muleqc:
__mulequc:
	jsr	__eqgetc	; @tmp is the value (we pull an extra byte
				; who cares)
	jsr	__multmpu
	jsr	__poptmp	; @tmp is back to the pointer, Y is 0
	sta	(@tmp),y
	rts


