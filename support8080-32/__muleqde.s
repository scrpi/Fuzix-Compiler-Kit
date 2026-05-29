;
;	HL * DE
;
	.export __muleqde
	.export __nearmuleq

__nearmuleq:
	;	TOS is pointer, HL is data
	xchg
	pop	h
	xthl
	;	HL is now pointer, DE is data
__muleqde:
	push	d
	mov	e,m
	inx	h
	mov	d,m
	dcx	h
	xthl
	call	__mulde
	xchg
	pop	h
	mov	m,e
	inx	h
	mov	m,d
	xchg
	ret
