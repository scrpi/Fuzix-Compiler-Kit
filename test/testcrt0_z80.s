;
;	Stub crt for running tests
;
	call	_main
	ld	a,l
	out	(0xFF),a

	.export	_printint

_printint:
	pop	hl
	pop	de
	push	de
	ld	a,e
	out	(0xFC),a
	ld	a,d
	out	(0xFD),a
	jp	(hl)

	.export	_printchar

_printchar:
	pop	hl
	pop	de
	push	de
	ld	a,e
	out	(0xFE),a
	jp	(hl)