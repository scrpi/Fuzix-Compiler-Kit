;
;	(HL) |= DE
;
	.export __oreqde
	.export __nearoreq
	.setcpu 8080

	.code

__nearoreq:
	;	TOS is pointer, HL is data
	xchg
	pop	h
	xthl
	;	HL is now pointer, DE is data
__oreqde:
	mov	a,m
	ora	e
	mov	m,a
	mov	e,a
	inx	h
	mov	a,m
	ora	d
	mov	m,a
	mov	d,a
	xchg
	ret

