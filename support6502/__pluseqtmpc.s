	.export __pluseqc
	.export __pluseqtmpc
	.export __pluseqtmpuc

__pluseqc:
	jsr	__poptmp
__pluseqtmpc:
__pluseqtmpuc:
	clc
	adc	(@tmp),y
	sta	(@tmp),y
	rts
