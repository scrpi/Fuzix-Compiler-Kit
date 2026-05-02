	.code

	.export __band
	.export __andtmp
	.export __andtmpu
__band:
	jsr __poptmp
__andtmp:
__andtmpu:
	and @tmp
	pha
	txa
	and @tmp+1
	tax
	pla
	rts
