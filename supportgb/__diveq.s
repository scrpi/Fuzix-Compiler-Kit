;
;	Divison /= %= operators
;
;	(TOS) /= HL etc
;

	.export __divequ
	.export __remequ
	.export __diveq
	.export __remeq
	.export __divequc
	.export __remequc
	.export __diveqc
	.export __remeqc

__divequ:
	call	__eqprep
	; HL is now the pointer
	push	hl
	ldi	a,(hl)
	ld	h,(hl)
	ld	l,a
	call	__divhlde
	; result is in HL
	jp	__eqpopouthl

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
	jp	__eqpopouthl

__remeq:
	call	__eqprep
	push	hl
	ldi	a,(hl)
	ld	h,(hl)
	ld	l,a
	call	__rem2opcon
	jp	__eqpopouthl

__divequc:
	call	__eqprep
	; HL is now the pointer
	push	hl
	ld	l,(hl)
	ld	h,0
	call	__divhlde
	; result is in HL
	ld	a,l
	jp	__eqpopoutc

__remequc:
	call	__eqprep
	; HL is now the pointer
	push	hl
	ld	l,(hl)
	ld	h,0
	call	__divhlde
	; result is in DE
	ld	a,e
	jp	__eqpopoutc

__diveqc:
	call	__eqprep
	push	hl
	ld	l,(hl)
	ld	h,0
	bit	7,l
	jr	z,nosex
	dec	h
nosex:
	call	__div2opcon
	ld	a,l
	jp	__eqpopoutc

__remeqc:
	call	__eqprep
	push	hl
	ld	l,(hl)
	ld	h,0
	bit	7,l
	jr	z,nosex2
	dec	h
nosex2:
	call	__rem2opcon
	ld	a,l
	jp	__eqpopoutc
