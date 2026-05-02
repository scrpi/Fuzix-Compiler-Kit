	.code

	.export __andeqtmp
	.export __andeqtmpu
	.export __andeq
__andeq:
	jsr __poptmp
__andeqtmp:
__andeqtmpu:
	ldy #0
	and (@tmp),y
	sta (@tmp),y
	pha
	txa
	iny
	and (@tmp),y
	sta (@tmp),y
	tax
	pla
	rts
