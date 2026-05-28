;
;		TOS = lval of object HL = amount
;
	.export __minuseq

	.setcpu 8080
	.code

__minuseq:
	call	__popeq
	; HL = ptr DE = value

	mov	a,m
	sub	e
	mov	m,a
	mov	e,a	; Save result into DE
	inx	h
	mov	a,m
	sbb	d
	mov	m,a
	mov	d,a	; Result now in DE also
	xchg		; into HL for return
	jmp	__reteq
