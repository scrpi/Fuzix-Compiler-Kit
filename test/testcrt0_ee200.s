;
;	EE200 wrapper for testing
;
	.code

	lda 0xE000
	xas
	jsr _main
	stbb (0xFFFF)

	.export _printchar

_printchar:
	ldab	3(s)
	stab	(0xFFFE)
	rsr

	.export _printint

_printint:
	ldb	2(s)
	stb	(0xFFFC)
	rsr
