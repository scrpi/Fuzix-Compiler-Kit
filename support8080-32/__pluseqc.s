;
;		TOS = lval of object L = amount
;
	.export __pluseqc
	.setcpu 8080

	.code

__pluseqc:
	call	__popeq
	mov	a,m
	add	e
	mov	m,a
	mov	l,a
	jmp	__reteq