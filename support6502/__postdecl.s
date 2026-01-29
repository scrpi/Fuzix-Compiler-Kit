;
;	(TOS) -= hireg:XA
;	Old contents of (TOS) returned
;
;	Can probably be optimized somewhat
;
	.export __postdecl

__postdecl:
	jsr	__poptmp
	; @tmp is now the pointer to the 32bit value
	ldy	#0
	sec
	sta	@tmp2
	lda	(@tmp),y
	pha
	sbc	@tmp2
	sta	(@tmp),y
	iny
	stx	@tmp2
	lda	(@tmp),y
	tax
	sbc	@tmp2
	sta	(@tmp),y
	iny
	lda	(@tmp),y
	sta	@tmp2
	sbc	@hireg
	sta	(@tmp),y
	iny
	lda	(@tmp),y
	sta	@tmp2+1
	sbc	@hireg+1
	sta	(@tmp),y
	lda	@tmp2
	sta	@hireg
	lda	@tmp2+1
	sta	@hireg+1
	pla
	rts
