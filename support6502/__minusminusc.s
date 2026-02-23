	.export	__minusmtmpc
	.export __minusmtmpuc
	.export __minusminusc

__minusminusc:
	jsr	__poptmp	; TOS into @tmp, preserve XA, Y is now 0
	jmp	domm
__minusmtmpc:
__minusmtmpuc:
	stx	@tmp+1		; save other half of working pointer
domm:
	ldy	#0
	sta	@tmp1
	lda	(@tmp),y	; low half
	pha
	sec
	sbc	@tmp1		; adjust
	sta	(@tmp),y	; store
	pla			; return old value
	rts
