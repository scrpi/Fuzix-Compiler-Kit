;
;	Store (@sp),y into XA return stored value
;
	.export __l_eq

	.code

__l_eq:
	sta	@tmp
	stx	@tmp+1
	lda	(@sp),y
	dey
	tax
	lda	(@sp),y
	; XA is now the value to store in (@tmp)
	ldy	#0
	sta	(@tmp),y
	iny
	pha
	txa
	sta	(@tmp),y
	pla
	rts
