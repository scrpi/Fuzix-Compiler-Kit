;
;	(TOS) << HL
;
	.export __shleq

__shleq:
	call	__eqprep
	push	hl
	ldi	a,(hl)
	ld	h,(hl)
	ld	l,a
	; HL is pointer, DE is shift amount
	call	__shl2opcon
	jp	__eqpopouthl

