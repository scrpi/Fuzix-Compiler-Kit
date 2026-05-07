;
;	(TOS) << HL
;
	.export __shleq

__shleq:
	call	__eqprep
	ld	a,e
	push	hl
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	ld	l,a
	; DE is the value L is the shift
	call	__shl2opcon
	jp	__eqpopout

