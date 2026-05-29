;
;	(HL) ^= DE
;
	.export __xoreqdec
	.export __nearxoreqc
	.setcpu 8080

	.code

__nearxoreqc:
	;	TOS is pointer, L is data
	xchg
	pop	h
	xthl
	;	HL is now pointer, E is data
__xoreqdec:
	mov	a,m
	xra	e
	mov	m,a
	mov	l,a
	ret
