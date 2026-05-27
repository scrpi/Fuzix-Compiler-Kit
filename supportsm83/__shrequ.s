;
;	(TOS) >> HL
;
	.export __shrequ

__shrequ:
	call	__eqprep
	ld	a,e
	push	hl
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	ld	l,a
	; DE is the value L is the shift
	call	__shr2opconu
	jp	__eqpopout

