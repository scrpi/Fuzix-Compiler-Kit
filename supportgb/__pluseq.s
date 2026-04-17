	.export __pluseq
	.export __pluseq2op
;
;	(TOS) += HL
;
__pluseq:
	ld	e,l
	ld	d,h
	ld	hl,sp+2
	call	__pluseq2op
	pop	de
	inc	sp
	inc	sp
	push	de
	ret

__pluseq2op:
;	(HL) += DE
	;	Get pointer
	ldi	a,(hl)
	ld	h,(hl)
	ld	l,a
	;	Now do additions
	ld	a,(hl)
	add	e
	ldi	(hl),a
	ld	e,a
	ld	a,(hl)
	adc	d
	ld	(hl),a
	ld	h,a
	ld	l,e
	ret

