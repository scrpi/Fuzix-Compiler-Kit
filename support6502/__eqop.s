;
;	Helpers for *= /= and friends
;
	.export __eqget
	.export __eqgetc
	.export __eqput

;
;	Get (TOS) into @tmp. Preserve XA
;	Retuns with Y = 2 (so in theory you can access the upper for a long)
;
__eqget:
	pha
	ldy	#0
	lda	(@sp),y
	sta	@tmp2
	iny
	lda	(@sp),y
	sta	@tmp2+1
	dey
	lda	(@tmp2),y
	sta	@tmp
	iny
	lda	(@tmp2),y
	sta	@tmp+1
	pla
	rts
;
;	Get (TOS) into @tmp. Preserve XA
;
__eqgetc:
	pha
	ldy	#0
	lda	(@sp),y
	sta	@tmp2
	iny
	lda	(@sp),y
	sta	@tmp2+1
	dey
	lda	(@tmp2),y
	sta	@tmp
	pla
	rts

;
;	Put XA into (TOS), pop TOS, preserve XA
;
__eqput:
	jsr	__poptmp
	; @tmp is now our pointer, Y is 0
	sta	(@tmp),y
	iny
	pha
	txa
	sta	(@tmp),y
	pla
	rts
