	.export	__minusmtmp
	.export __minusmtmpu
	.export __postdec
	.export __mminusy
	.export __mminus1
	.export __mminus2
	.export __mminus4
	.export __l_mminus
	.export __l_mminus1
	.export __l_mminus2
	.export __l_mminus3
	.export __l_mminus4
	.export __l_mminusa

__postdec:
	jsr	__poptmp	; TOS into @tmp, preserve XA, Y is now 0
__minusmtmp:
__minusmtmpu:
	sta	@tmp1
	stx	@tmp1+1		; value to subtract from (@tmp)
	ldy	#0
do_mm:
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

__mminus1:
	ldy	#1
__mminusy:
	sty	@tmp1
	ldy	#0
	sty	@tmp1+1
	sta	@tmp
	stx	@tmp+1
	jmp	do_mm
__mminus2:
	ldy	#2
	bne	__mminusy
__mminus4:
	ldy	#4
	bne	__mminusy

__l_mminus4:
	lda	#4
	bne	__l_mminusa
__l_mminus3:
	lda	#3
	bne	__l_mminusa
__l_mminus2:
	lda	#2
	bne	__l_mminusa
__l_mminus1:
	lda	#1
__l_mminusa:
	ldx	#0
__l_mminus:
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
	beq	do_mm
