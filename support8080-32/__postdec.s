;
;		TOS = lval of object HL = amount
;
	.export __postdec
	.setcpu 8080

	.code

__postdec:
	call	__popeq
	mov	a,m
	sta	__tmp
	sub	e
	mov	m,a
	inx	h
	mov	a,m
	sta	__tmp+1
	sbb	d
	mov	m,a
	lhld	__tmp
	jmp	__reteq
