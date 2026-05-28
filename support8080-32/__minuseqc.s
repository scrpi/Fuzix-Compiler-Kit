;
;		TOS = lval of object L = amount
;
	.export __minuseqc
	.export __minusequc

	.setcpu 8080
	.code

__minuseqc:
__minusequc:
	call	__popeq
	mov	a,m
	sub	e
	mov	m,a
	mov	l,a
	jmp	__reteq
