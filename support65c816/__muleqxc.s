	.65c816
	.a16
	.i16

	.export __muleqxc
	.export __muleqxcu

	; A is ptr X is a value
__muleqxcu:
__muleqxc:
	stx @tmp
	tax
	sep #0x20
	lda 0,x
	rep #0x20
	phx
	ldx @tmp
	jsr __mulx
	plx
	sep #0x20
	sta 0,x
	rep #0x20
	rts
