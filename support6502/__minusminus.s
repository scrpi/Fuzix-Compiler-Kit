	.export	__minusminustmp
	.export __minusminustmpu
	.export __minusminus

__minusminus:
	jsr	__poptmp	; TOS into @tmp, preserve XA, Y is now 0
__minusminustmp:
__minusminustmpu:
	ldy	#0

	sta	@tmp1
	stx	@tmp1+1		; value to subtract from (@tmp)

	lda	(@tmp),y	; low half
	pha			; save old value
	sec
	sbc	@tmp1		; adjust
	sta	(@tmp),y	; store
	iny
	lda	(@tmp),y
	tax			; save old upper into X
	sbc	@tmp1+1		; subtract high half
	sta	(@tmp),y	; and save
	pla			; recover low half of original
	rts
