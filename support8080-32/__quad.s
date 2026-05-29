;
;	Helpers for load/store of 4 byte locals
;
	.export __ldquad
	.export __stquad
	.setcpu 8080

	.code

__ldquad:
	; HL is offset from SP of high byte
	dad	sp
	mov	d,m
	dcx	h
	mov	e,m
	dcx	h
	xchg
	shld	__hireg
	xchg
	mov	d,m
	dcx	h
	mov	e,m
	xchg
	ret

__stquad:
	; DE is offset from SP of low byte
	xchg
	dad	sp
	push	d
	mov	m,e
	inx	h
	mov	m,d
	inx	h
	xchg
	lhld	__hireg
	xchg
	mov	m,e
	inx	h
	mov	m,d
	pop	h
	ret
