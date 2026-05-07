
;;	(HL) ^ DE
;
	.export __bor2op

__bor2op:
	ldi	a,(hl)
	or	e
	ld	e,a
	ld	a,(hl)
	or	d
	ld	d,a
	ret
