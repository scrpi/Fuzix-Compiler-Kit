
;;	(HL) | DE
;
	.export __bor2op
	.export __or

__or:
	ld	hl,sp+2
	call	__bor2op
	pop	hl
	pop	de
	jp	(hl)

__bor2op:
	ldi	a,(hl)
	or	e
	ld	e,a
	ld	a,(hl)
	or	d
	ld	d,a
	ret
