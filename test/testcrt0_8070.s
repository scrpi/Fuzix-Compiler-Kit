;
;	Stub for running tests
;
	.code
	ld p1,=0x8000
	ld p3,=_main
	jsr _main
	ld p1,#0xFEFF
	st a,0,p1

	.export _printint

_printint:
	ld ea,2,sp
	ld p2,#0xFEFC
	st ea,0,p2
	ret

	.export _printchar

_printchar:
	ld ea,2,sp
	ld p2,#0xFEFE
	st a,0,p2
	ret

	.export __tmp
	.export __tmp2
	.export __hireg

	.dp
__tmp:
	.word 0
__tmp2:
	.word 0
__hireg:
	.word 0
