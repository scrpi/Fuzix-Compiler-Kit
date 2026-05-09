	.export __reql4

__reql4:
	sta	(@reg4),y
	pha
	txa
	iny
	sta	(@reg4),y
	iny
	lda	@hireg
	sta	(@reg4),y
	iny
	lda	@hireg+1
	sta	(@reg4),y
	pla
	rts
