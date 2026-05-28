;
;		(TOS) *= HL
;

	.export __muleq
	.setcpu 8080
	.code

__muleq:
	call	__popeq
	; Now we are doing (HL) * DE
	push	d
	mov	e,m
	inx	h
	mov	d,m
	dcx	h
	xthl
	; We are now doing HL * DE and the address we want is TOS
	call __mulde
	; Return is in HL
	xchg
	pop	h
	mov	m,e
	inx	h
	mov	m,d
	xchg
	jmp	__reteq
