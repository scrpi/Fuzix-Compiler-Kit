;
;		(HL) &= E
;
	.export __andeqdec
	.export __nearandeqc
	.setcpu 8080

	.code

__nearandeqc:
	;	TOS is pointer, HL is data
	xchg
	pop	h
	xthl
	;	HL is now pointer, E is data
__andeqdec:
	mov	a,m
	ana	e
	mov	m,a
	mov	l,a
	ret
