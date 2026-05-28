	.export __minuseql
	.setcpu	8080

	.code

__minuseql:
	call	__popeq
	; HL is pointer, hireg:de amount to add

	mov	a,m
	sub	e
	mov	m,a
	mov	e,a
	inx	h
	mov	a,m
	sbb	d
	mov	m,a
	mov	d,a
	inx	h
	push	d

	xchg
	lhld	__hireg
	xchg

	mov	a,m
	sbb	e
	mov	m,a
	mov	e,a
	inx	h
	mov	a,m
	sbb	d
	mov	m,a
	mov	d,a

	xchg
	shld	__hireg

	pop	h
	jmp	__reteq