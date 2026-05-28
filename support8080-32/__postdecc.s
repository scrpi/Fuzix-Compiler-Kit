;
;		TOS = lval of object HL = amount
;
	.export __postdecc
	.setcpu 8080

	.code

__postdecc:
	call	__popeq
	mov	a,m
	mov	d,a
	sub	e
	mov	m,a
	mov	l,d
	jmp	__reteq
