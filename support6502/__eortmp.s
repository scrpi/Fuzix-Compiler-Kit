	.code

	.export __xor
	.export __eortmp
	.export __eortmpu
__xor:
	jsr __poptmp
__eortmp:
__eortmpu:
	eor @tmp
	pha
	txa
	eor @tmp+1
	tax
	pla
	rts
