	.code ; (at 0x0200)

	.65c02

start:	ldx	#0xFF
	txs		; stack at 01FF
	stz	sp
	lda	#0xFD	; user stack at FD00
	sta	sp+1
	jsr	_main
	; return and exit (value is in XA)
	sta	$FEFF
	; Write to FEFF terminates

	.export _printint

_printint:
	lda	(@sp)
	sta	$FEFC
	iny
	lda	(@sp),y
	sta	$FEFD
	iny
	jmp	__addysp

	.export	_printchar

_printchar:
	lda	(@sp)
	sta	$FEFE
	ldy	#2
	jmp	__addysp
