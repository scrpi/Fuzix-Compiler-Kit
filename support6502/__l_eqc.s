;
;	Store (@sp),y into XA return stored value
;
	.export __l_eqc

	.code

__l_eqc:
	sta	@tmp
	stx	@tmp+1
	lda	(@sp),y
	; A is now the value to store in (@tmp)
	ldy	#0
	sta	(@tmp),y
	rts
