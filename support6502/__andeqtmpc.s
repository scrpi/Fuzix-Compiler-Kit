	.code

	.export __andeqtmpc
	.export __andeqtmpuc
__andeqtmpc:
__andeqtmpuc:
	ldy #0
	stx @tmp+1
	and (@tmp),y
	sta (@tmp),y
	rts
