	.code

	.export __adceqtmpc
	.export __adceqtmpuc
__adceqtmpc:
__adceqtmpuc:
	ldy #0
	stx @tmp+1
	clc
	adc (@tmp),y
	sta (@tmp),y
	rts
