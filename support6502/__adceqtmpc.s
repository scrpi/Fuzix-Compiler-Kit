	.code

	.export __adceqtmpc
	.export __adceqtmpuc
__adceqtmpc:
__adceqtmpuc:
	ldy #0
	clc
	adc (@tmp),y
	sta (@tmp),y
	rts
