;
;		TOS = lval of object L = mask
;
	.export __oreqc

	.setcpu 8080
	.code

__oreqc:
	call	__popeq
	mov	a,e
	ora	m
	mov	m,a
	mov	l,a
	jmp	__reteq
