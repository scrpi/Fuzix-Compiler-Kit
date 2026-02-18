	.export __pluseqtmp

__pluseqtmp:
__pluseqtmpu:
	clc
	adc	(@tmp),y
	sta	(@tmp),y
	pha
	iny
	txa
	adc	(@tmp),y
	sta	(@tmp),y
	tax
	pla
	rts
