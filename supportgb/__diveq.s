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
	push	de
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	pop	hl
	call	__divdehl
	; result is in DE
	jp	__eqpopout

__remequ:
	call	__eqprep
	; HL is now the pointer
	push	hl
	push	de
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	pop	hl
	call	__divdehl
	; result is in HL
	jp	__eqpopouthl

__diveq:
	call	__eqprep
	push	hl
	push	de
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	pop	hl
	call	__div2opcon
	jp	__eqpopout

__remeq:
	call	__eqprep
	push	hl
	push	de
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	pop	hl
	call	__rem2opcon
	jp	__eqpopout

__divequc:
	call	__eqprepc
	; HL is now the pointer
	; (HL) / A
	push	hl
	ld	e,(hl)
	ld	d,0
	ld	l,a
	ld	h,0
	call	__divdehl
	; result is in DE
	ld	a,e
	jp	__eqpopoutc

__remequc:
	call	__eqprepc
	; HL is now the pointer
	push	hl
	ld	e,(hl)
	ld	d,0
	ld	l,a
	ld	h,0
	call	__divdehl
	; result is in HL
	ld	a,l
	jp	__eqpopoutc

__diveqc:
	call	__eqprepc
	push	hl
	ld	e,(hl)
	ld	d,0
	bit	7,e
	jr	z,nosex
	dec	d
nosex:
	ld	l,a
	ld	h,0
	bit	7,l
	jr	z,nosexb
	dec	h
nosexb:
	call	__div2opcon
	ld	a,e
	jp	__eqpopoutc

__remeqc:
	call	__eqprepc
	push	hl
	ld	e,(hl)
	ld	d,0
	bit	7,e
	jr	z,nosex2
	dec	d
nosex2:
	ld	l,a
	ld	h,0
	bit	7,l
	jr	z,nosex2b
	dec	h
nosex2b:
	call	__rem2opcon
	ld	a,e
	jp	__eqpopoutc
