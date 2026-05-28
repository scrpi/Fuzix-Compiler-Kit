;
;		TOS = lval of object L = mask
;
		.export __andeqc

		.setcpu 8080
		.code
__andeqc:
		call	__popeq
		mov	a,e
		ana	m
		mov	m,a
		mov	l,a
		jmp	__reteq
