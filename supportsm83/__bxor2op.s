;
;	(HL) ^ DE
;
	.export __bxor2op
	.export __xor

__xor:
	ld	hl,sp+2
	call	__bxor2op
	pop	hl
	pop	af
	jp	(hl)

__bxor2op:
	ldi	a,(hl)
	xor	e
	ld	e,a
	ld	a,(hl)
	xor	d
	ld	d,a
	ret
