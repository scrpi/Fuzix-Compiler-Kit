	.code ; (at 0x0100)

	.setcpu	6803
start:
	clr	@zero
	ldd	#1
	std	@one
	lds	#$FDFF
	jsr	_main
	; return and exit (value is in XA)
	stab	$FEFF
	; Write to FEFF terminates

	.export _printint
_printint:
	tsx
	ldab 3,x
	ldaa 2,x
	staa $fefc
	stab $fefc+1
	rts

	.export _printchar
_printchar:
	tsx
	ldab 3,x
	stab $FEFE
	rts
