	.65c816

	.code ; (at 0x0200)

	.a8
	.i8
start:
	cld
	clc
	xce
	.a16
	.i16
	rep	#0x30
	ldx	#0x1FF
	txs		; stack at 01FF
	ldy	#0xFE00	; C stack
	jsr	_main
	; return and exit (value is in XA)
	sta	$FEFF
	; Write to FEFF terminates

	.export _printint

_printint:
	lda	0,y
	sta	$FEFC
	iny
	iny
	rts

	.export	_printchar

_printchar:
	lda	0,y
	sep	#0x20
	.a8
	sta	$FEFE
	rep	#0x20
	.a16
	iny
	iny
	rts
