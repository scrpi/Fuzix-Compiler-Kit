;
;	(TOS) << HL
;
	.export __shreq

__shreq:
	call	__eqprep
	push	hl
	ldi	a,(hl)
	ld	h,(hl)
	ld	l,a
	; HL is pointer, DE is shift amount
	call	__shr2opcon
	jp	__eqpopouthl

