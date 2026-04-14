	.65c816
	.a16
	.i16

	.export __diveqxuc

	; A is ptr X is a value to divide by
__diveqxuc:
	stx @tmp
	tax
	lda #0
	sep #$20
	.a8
	lda 0,x
	stz @tmp+1
	rep #$20
	.a16
	phx
	ldx @tmp
	jsr __divxu
	plx
	sep #$20
	sta 0,x
	rep #$20
	rts
