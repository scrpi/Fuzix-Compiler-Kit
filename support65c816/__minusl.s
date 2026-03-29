	.65c816
	.a16
	.i16

	.export __minusl

__minusl:
	; TOS - hireg:a
	sta @tmp
	lda 0,y
	sec
	sbc @tmp
	tax
	lda 2,y
	sbc @hireg
	sta @hireg
	txa
	jmp __fnexit4
