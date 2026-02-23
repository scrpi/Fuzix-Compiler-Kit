	.code

	.export __eoreqtmpc
	.export __eoreqtmpuc
__eoreqtmpc:
__eoreqtmpuc:
	ldy #0
	stx @tmp+1
	eor (@tmp),y
	sta (@tmp),y
	rts
