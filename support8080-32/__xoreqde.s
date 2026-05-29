;
;	(HL) ^= DE
;
	.export __xoreqde
	.export __nearxoreq
	.setcpu 8080

	.code

__nearxoreq:
	;	TOS is pointer, HL is data
	xchg
	pop	h
	xthl
	;	HL is now pointer, DE is data
__xoreqde:
	mov	a,m
	xra	e
	mov	m,a
	mov	e,a
	inx	h
	mov	a,m
	xra	d
	mov	m,a
	mov	d,a
	xchg
	ret

