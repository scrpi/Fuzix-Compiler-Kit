;
;	Helper routines for /= and similar ops
;
	.export __eqprep
	.export __eqpopout
	.export __eqpopoutc

__eqprep:
	ld	e,l
	ld	d,h
	ld	hl,sp+2
	ldi	a,(hl)
	ld	h,(hl)
	ld	l,a
	; HL is now the pointer
	ret

;	End code for some eq ops. Jumped to - pops the variable
;	address, writes DE into it and returns it as HL having done
;	a stack clean
__eqpopout:
	pop	hl
	ld	(hl),e
	inc	hl
	ld	(hl),d
	ld	h,d
	ld	l,e
	pop	de
	inc	sp
	inc	sp
	push	de
	ret

__eqpopoutc:
	pop	hl
	ld	(hl),a
	ld	l,e
	pop	de
	inc	sp
	inc	sp
	push	de
	ret
