;
;	(HL) |= E
;
	.export __oreqdec
	.export __nearoreqc
	.setcpu 8080

	.code

__nearoreqc:
	;	TOS is pointer, HL is data
	xchg
	pop	h
	xthl
	;	HL is now pointer, E is data
__oreqdec:
	mov	a,m
	ora	e
	mov	m,a
	mov	l,a
	ret

