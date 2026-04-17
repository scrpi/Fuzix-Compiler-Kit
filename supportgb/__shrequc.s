;
;	(TOS) << HL
;
	.export __shrequc

__shrequc:
	call	__eqprep
	push	hl
	ld	a,e		; count
	and	7
	ld	e,a
	ld	a,(hl)		; working value
	jr	z, nowork
loop:	srl	a
	dec	e
	jr	nz,loop
nowork:
	jp	__eqpopoutc

