	.export	__minusmtmpc
	.export __minusmtmpuc
	.export __minusminusc

__minusminusc:
	jsr	__poptmp	; TOS into @tmp, preserve XA, Y is now 0
	jmp	doop
__minusmtmpc:
__minusmtmpuc:
	stx	@tmp+1
	ldy	#0
doop:
	eor	#0xFF
	sec
	sta	@tmp1
	lda	(@tmp),y
	tax
	adc	@tmp1
	sta	(@tmp),y
	txa
	rts
