	.65c816
	.a16
	.i16

	.export __diveqxc

	; A is ptr X is a value to divide by
__diveqxc:
	stx @tmp
	tax
	lda #0
	sep #0x20
	stz @tmp+1
	lda 0,x
	rep #0x20
	bpl pve1
	ora #0xFF00
pve1:
	phx
	ldx @tmp
	cpx #0x80
	bcc noneg
	dec @tmp+1
	ldx @tmp	
noneg:
	jsr __divx
	plx
	sep #0x20
	sta 0,x
	rep #0x20
	rts
