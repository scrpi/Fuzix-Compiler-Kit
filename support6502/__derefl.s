;
;	Load hireg:xa from (XA)
;
	.export __dereff
	.export __derefl
	.export __dereff_a
	.export __derefl_a
	.export __derefly

__derefl_a:
__dereff_a:
	jsr	__asp
__dereff:
__derefl:
	ldy	#3
__derefly:
	sta	@tmp
	stx	@tmp+1
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

