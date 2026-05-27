;
;	(TOS) << HL
;
	.export __shrequc

__shrequc:
	call	__eqprepc
	push	hl
	and	7		; count
	ld	e,a
	ld	a,(hl)		; working value
	jr	z, nowork
loop:	srl	a
	dec	e
	jr	nz,loop
nowork:
	jp	__eqpopoutc

