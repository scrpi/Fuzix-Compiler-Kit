	.65c816
	.a16
	.i16

	.export __diveqxuc

	; A is ptr X is a value to divide by
__diveqxuc:
	stx @tmp
	tax
	sep #$20
	lda 0,x
	rep #$20
	phx
	ldx @tmp
	jsr __divxu
	plx
	sep #$20
	sta 0,x
	rep #$20
	rts
