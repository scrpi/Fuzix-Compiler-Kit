;
;	16bit multiply forms
;
	.export __mul2op
	.export	__mul2opcon
	.export __mulde
	.export __muleq
	.export __muleqc
	.export __mul

;	DE * (HL)
__mul2op:
	ldi	a,(hl)
	ld	h,(hl)
	ld	l,a
__mul2opcon:
;
;	DE * HL
;
__mulde:
	ld	b,h		; copy value over
	ld	c,l
	ld	hl,0
	ld	a,d		; upper half of work in A for speed
	ld	d,16
loop:
	add	hl,hl		; shift result
	rl	e
	rla
	jr	nc, noset	; not a 1 bit in this column
	add	hl,bc		; add in the other half
noset:	dec	d
	jr	nz, loop
	; result is in HL
	ld	d,h
	ld	e,l
	ret

__muleq:
	call	__eqprep
	push	hl
	call	__mul2op
	jp	__eqpopout

__muleqc:
	call	__eqprep
	push	hl
	ld	l,(hl)
	ld	h,0
	call	__mulde
	ld	a,l
	jp	__eqpopoutc


__mul:
	;	TOS * DE
	ld	hl,sp+2
	ldi	a,(hl)
	ld	h,(hl)
	ld	l,a
	call	__mulde
	pop	hl
	inc	sp
	inc	sp
	jp	(hl)
