;
;	Dereference the point at (@sp),y
;	Then dereference the offset of that in X
;	and get the value
;
	.export __lderefc
	.export __lderefc0

__lderefc0:
	ldy	#0
__lderefc:
	lda	(@sp),y
	sta	@tmp	
	iny
	lda	(@sp),y
	sta	@tmp+1
	txa
	tay
	lda	(@tmp),y
	ldx	#0
	rts
