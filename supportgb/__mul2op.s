;
;	16bit multiply forms
;
	.export __mul2op
	.export	__mul2opcon
	.export __mulde

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
	push	bc

	ld	b,h		; save old upper byte

	ld	a,l		; work on old lower
	ld	c,8

	ld	hl,0		; accumulator for the shift/adds

low:	rra
	jr	nc, noadd1
	add	hl,de
noadd1:	sla	l		; noxchg on SM83
	rl	h		; so use the shifts
	dec	c
	jr	nz, low

	ld	a,b
	ld	c,8

hi:	rra
	jr	nc,noadd2
	add	hl,de
noadd2:	sla	l
	rl	h
	dec	c
	jr	nz,hi

	; result is in HL

	pop	bc
	ret

