	.export __reql2

__reql2:
	sta	(@reg2),y
	pha
	txa
	iny
	sta	(@reg2),y
	iny
	lda	@hireg
	sta	(@reg2),y
	iny
	lda	@hireg+1
	sta	(@reg2),y
	pla
	rts
