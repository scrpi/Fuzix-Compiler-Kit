;
;		TOS = lval of object L = mask
;
	.export __xoreqc
	.setcpu 8080

	.code

__xoreqc:
	call	__popeq
	mov	a,e
	xra	m
	mov	m,a
	mov	l,a
	jmp	__reteq
