;
;	Stub crt for running tests
;
	ld	sp,0xF000
	call	_main
	ld	a,l
	ld 	(0xFFFF),a

	.export	_printint

_printint:
	pop	hl
	pop	de
	push	de
	ld	a,e
	ld 	(0xFFFC),a
	ld	a,d
	ld 	(0xFFFC),a
	jp	(hl)

	.export	_printchar

_printchar:
	pop	hl
	pop	de
	push	de
	ld	a,e
	ld	(0xFFFE),a
	jp	(hl)