;
;	(TOS) << HL
;
	.export __shrequ

__shrequ:
	call	__eqprep
	push	hl
	ldi	a,(hl)
	ld	h,(hl)
	ld	l,a
	; HL is pointer, DE is shift amount
	call	__shr2opconu
	jp	__eqpopouthl

