;
;	Negate XA
;
	.export __negate

__negate:
	clc
	eor	#0xFF
	adc	#1
	pha
	txa
	eor	#0xFF
	adc	#0
	tax
	rts
