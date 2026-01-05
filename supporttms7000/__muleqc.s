	.export __muleqc
	.export __mulequc   	

	.code

__muleqc:
__mulequc:
	; stack holds ptr instead in this case
	call	@__pop10

	; Get values
	lda	*r11

	mpy	a,r5
	sta	*r11
	mov	a,r5
	rets
