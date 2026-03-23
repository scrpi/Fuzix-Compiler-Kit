;
;	Unsigned 16x16 mul
;
	.export __mul
	.export __mulu
	.export __multmp
	.export __multmpu
	.export __l_mul
	.export __muleq
	.export __mulequ

__l_mul:
	jsr	__ytmp
	jmp	__multmp
__mul:
__mulu:
	jsr	__poptmp
__multmp:
__multmpu:
	; XA * tmp

	sta	@tmp1
	stx	@tmp1+1

	lda	#0
	sta	@tmp2+1
	ldy	#16

nextbit:
	asl	a
	rol	@tmp2+1

	rol	@tmp
	rol	@tmp+1

	bcc	noadd

	clc
	adc	@tmp1
	tax
	lda	@tmp1+1
	adc	@tmp2+1
	sta	@tmp2+1
	txa

noadd:	dey
	bne	nextbit
	ldx	@tmp2+1
	rts

__muleq:
__mulequ:
	jsr	__eqget		; @tmp is the value
	jsr	__multmpu
	jmp	__eqput
