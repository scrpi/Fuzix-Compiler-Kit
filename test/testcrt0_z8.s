
	.code
	.ds 12		; vectors
start:
	; Stack Ptr FF00 (FEFF first byte of stack)
	clr 0xFF
	ld 0xFE,#0xFF
	; P01M Stack external, high address bits enable
	ld 0xF8,#0x92
	srp #0x10
	call __reginit
	call _main
	; Write result to FFFF external data
	ld r14,#0xFF
	ld r15,r14
	lde @rr14,r3

	.export _printint

_printint:
	ld r2,#255
	ld r3,#252
	ld r15,#4
	call __garg12r2
	lde @rr2, r12
	incw rr2
	lde @rr2, r13
;
	jp __cleanup2

	.export _printchar

_printchar:
	ld r2,#255
	ld r3,#254
	push r3
	push r2
	ld r15,#6
	call __gargr2
	pop r14
	pop r15
	lde @rr14, r3
;
	jp __cleanup2
