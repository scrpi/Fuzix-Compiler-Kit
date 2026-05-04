;
;	Used for longer distance derefs - rare this happens
;
;	Dereference the point at (@sp),ya
;	Then dereference the offset of that in X
;	and get the value
;
	.export __lderefya

__lderefya:
	clc
	adc	@sp		; low of offset
	sta	@tmp2
	tya
	adc	@sp+1
	sta	@tmp2+1
	ldy	#0
	lda	(@tmp2),y
	sta	@tmp	
	iny
	lda	(@tmp2),y
	sta	@tmp+1
	txa
	tay
	lda	(@tmp),y
	tax
	dey
	lda	(@tmp),y
	rts
