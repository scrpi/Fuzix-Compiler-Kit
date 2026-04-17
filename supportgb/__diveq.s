;
;	Divison /= %= operators
;
;	(TOS) /= HL etc
;

	.export __divequ
	.export __remequ
	.export __diveq
	.export __remeq

__divequ:
	call	__eqprep
	; HL is now the pointer
	push	hl
	ldi	a,(hl)
	ld	h,(hl)
	ld	l,a
	call	__divhlde
	; result is in HL
	ld	e,l
	ld	d,h
	jp	__eqpopout

__remequ:
	call	__eqprep
	; HL is now the pointer
	push	hl
	ldi	a,(hl)
	ld	h,(hl)
	ld	l,a
	call	__divhlde
	; result is in DE
	pop	hl
	jp	__eqpopout

__diveq:
	call	__eqprep
	push	hl
	ldi	a,(hl)
	ld	h,(hl)
	ld	l,a
	call	__div2opcon
	ld	e,l
	ld	h,d
	jp	__eqpopout

__remeq:
	call	__eqprep
	push	hl
	ldi	a,(hl)
	ld	h,(hl)
	ld	l,a
	call	__rem2opcon
	ld	e,l
	ld	h,d
	jp	__eqpopout
