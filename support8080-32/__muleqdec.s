;
;	L * E
;
	.export __muleqdec
	.export __nearmuleqc

__nearmuleqc:
	;	TOS is pointer, HL is data
	xchg
	pop	h
	xthl
	;	HL is now pointer, DE is data
__muleqdec:
	push	d
	mov	e,m
	xthl
	call	__mulde
	mov	a,l
	pop	h
	mov	m,a
	mov	l,a
	ret
