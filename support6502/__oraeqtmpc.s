	.code

	.export __oraeqtmpc
	.export __oraeqtmpuc
__oraeqtmpc:
__oraeqtmpuc:
	ldy #0
	ora (@tmp),y
	sta (@tmp),y
	rts
