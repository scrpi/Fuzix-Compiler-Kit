;
;	Load hireg:xa from (XA)
;
	.export __dereff
	.export __derefl
	.export __dereff_a
	.export __derefl_a

__derefl_a:
__dereff_a:
	jsr	__asp
__dereff:
__derefl:
	sta	@tmp
	stx	@tmp+1
	ldy	#3
	lda	(@tmp),y
	sta	@hireg+1
	dey
	lda	(@tmp),y
	sta	@hireg
	dey
	lda	(@tmp),y
	tax
	dey
	lda	(@tmp),y
	rts

