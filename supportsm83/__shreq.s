;
;	(TOS) >> DE
;
	.export __shreq

__shreq:
	call	__eqprep
	ld	a,e
	push	hl
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	ld	l,a
	; DE is the value L is the shift
	call	__shr2opcon
	jp	__eqpopout

