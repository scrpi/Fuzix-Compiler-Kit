;
;	Unsigned 16x16 mul
;
	.export __mulc
	.export __muluc
	.export __multmpc
	.export __multmpuc

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
