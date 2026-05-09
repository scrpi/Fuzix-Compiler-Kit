	.export __reql3

__reql3:
	sta	(@reg3),y
	pha
	txa
	iny
	sta	(@reg3),y
	iny
	lda	@hireg
	sta	(@reg3),y
	iny
	lda	@hireg+1
	sta	(@reg3),y
	pla
	rts
