	.export __reql1

__reql1:
	sta	(@reg1),y
	pha
	txa
	iny
	sta	(@reg1),y
	iny
	lda	@hireg
	sta	(@reg1),y
	iny
	lda	@hireg+1
	sta	(@reg1),y
	pla
	rts
