	.65c816
	.a16
	.i16

	.export __plusl

__plusl:
	clc
	adc 0,y
	tax
	lda @hireg
	adc 2,y
	sta @hireg
	txa
	rts
