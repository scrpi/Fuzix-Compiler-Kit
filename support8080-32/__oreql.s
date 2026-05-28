	.export __oreql
	.setcpu 8080

	.code

__oreql:
	call	__popeq
	mov	a,e
	ora	m
	mov	e,a
	mov	m,a
	inx	h
	mov	a,d
	ora	m
	mov	d,a
	mov	m,a
	inx	h
	push	d		; save the lower result
	; Upper word
	xchg
	lhld	__hireg
	xchg
	mov	a,e
	ora	m
	mov	e,a
	mov	m,a
	inx	h
	mov	a,d
	ora	m
	mov	m,a
	mov	h,a
	mov	l,e
	shld	__hireg
	pop	h
	jmp	__reteq
