	.export __pluseqtmp
	.export __pluseqtmpu
	.export __pluseq

__pluseq:
	jsr	__poptmp
__pluseqtmp:
__pluseqtmpu:
	ldy	#0
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
