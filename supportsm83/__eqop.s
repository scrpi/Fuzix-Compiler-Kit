;
;	Helper routines for /= and similar ops
;
	.export __eqprep
	.export __eqpopout
	.export __eqpopouthl
	.export __eqpopoutdebc
	.export __eqprepc
	.export __eqpopoutc

__eqprep:
	ld	hl,sp+4
	ldi	a,(hl)
	ld	h,(hl)
	ld	l,a
	; HL is now the pointer
	ret

__eqprepc:
	;	Data is in A
	ld	hl,sp+4
	ld	e,(hl)
	inc	hl
	ld	h,(hl)
	ld	l,e
	; HL is now the pointer
	ret

;	End code for some eq ops. Jumped to - pops the variable
;	address, writes DE into it and returns it as HL having done
;	a stack clean
__eqpopouthl:
	ld	e,l
	ld	d,h
__eqpopout:
	pop	hl
	ld	(hl),e
	inc	hl
	ld	(hl),d
	pop	hl
	inc	sp
	inc	sp
	jp	(hl)

__eqpopoutc:
	pop	hl
	ld	(hl),a
	pop	hl
	inc	sp
	inc	sp
	jp	(hl)

__eqpopoutdebc:
	pop	hl
	ld	(hl),e
	inc	hl
	ld	(hl),d
	inc	hl
	ld	(hl),c
	inc	hl
	ld	(hl),b
	pop	hl
	inc	sp
	inc	sp
	jp	(hl)
