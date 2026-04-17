;
;	(TOS) << HL
;
	.export __shreqc

__shreqc:
	call	__eqprep
	push	hl
	ld	a,e		; count
	and	7
	ld	e,a
	ld	a,(hl)		; working value
	jr	z, nowork
loop:	sra	a
	dec	e
	jr	nz,loop
nowork:
	jp	__eqpopoutc

