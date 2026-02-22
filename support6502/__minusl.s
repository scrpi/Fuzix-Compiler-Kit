;
;	This one gets used when we can't optimise a 32bit expression
;	into a simpler form for subtract.
;
;	At this point we need to do (TOS) - hireg:XA which is backwards
;	to ideal. Mostly though we need to focus on not needing to call this
;
	.export __minusl

__minusl:
	ldy	#0
	sta	@tmp
	lda	(@sp),y
	sec
	sbc	@tmp
	pha			; recovered in __incsp4
	iny
	stx	@tmp+1
	lda	(@sp),y
	sbc	@tmp+1
	tax
	iny
	lda	(@sp),y
	sbc	@hireg
	sta	@hireg
	iny
	lda	(@sp),y
	sbc	@hireg+1
	sta	@hireg+1
	jmp	__incsp4
