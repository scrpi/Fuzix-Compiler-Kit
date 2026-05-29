;
;		(HL) &= DE
;
	.export __andeqde
	.export __nearandeq
	.setcpu 8080

	.code

__nearandeq:
	;	TOS is pointer, HL is data
	xchg
	pop	h
	xthl
	;	HL is now pointer, DE is data
__andeqde:
	mov	a,m
	ana	e
	mov	m,a
	mov	e,a
	inx	h
	mov	a,m
	ana	d
	mov	m,a
	mov	d,a
	xchg
	ret

