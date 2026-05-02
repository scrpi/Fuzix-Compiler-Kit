	.code

	.export __or
	.export __oratmp
	.export __oratmpu
__or:
	jsr __poptmp
__oratmp:
__oratmpu:
	ora @tmp
	pha
	txa
	ora @tmp+1
	tax
	pla
	rts
