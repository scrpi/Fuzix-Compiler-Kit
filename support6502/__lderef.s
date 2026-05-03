;
;	Dereference the point at (@sp),y
;	Then dereference the offset of that in X
;	and get the value
;
	.export __lderef
	.export __lderef0

__lderef0:
	ldy	#0
__lderef:
	lda	(@sp),y
	sta	@tmp	
	iny
	lda	(@sp),y
	sta	@tmp+1
	txa
	tay
	lda	(@tmp),y
	tax
	dey
	lda	(@tmp),y
	rts

	