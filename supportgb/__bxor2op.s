;
;	(HL) ^ DE
;
	.export __bxor2op

__bxor2op:
	ldi	a,(hl)
	xor	e
	ld	e,a
	ld	a,(hl)
	xor	d
	ld	d,a
	ret
