	.65c816
	.a16
	.i16

	.export __diveqxc

	; A is ptr X is a value to divide by
__diveqxc:
	stx @tmp
	tax
	sep #0x20
	lda 0,x
	rep #0x20
	phx
	ldx @tmp
	jsr __divx
	plx
	sep #0x20
	sta 0,x
	rep #0x20
	rts
