;
;	Core division operation	HL / DE unsigned
;	Produces both result and remainder
;
	.export __divhlde

	.export __div2opcon
	.export __rem2opcon
	.export __div2opconu
	.export __rem2opconu
	.export __div2op
	.export __rem2op
	.export __div2opu
	.export __rem2opu

dodiv2opcon:
	;	HL / DE signed. Track state in C
	;	Caller does any final negation
	bit	7,h
	jr	z,pve1
	inc	c
	call	__negate
pve1:
	bit	7,d
	jr	z, __divhlde
	bit	7,c
	jr	nz, ismod
	inc	c
ismod:
	inc	de
	ld	a,d
	cpl
	ld	d,a
	ld	a,e
	cpl	
	ld	e,a
	;	HL/DE unsigned
__divhlde:
	push	bc
;
;	This is the standard algorithm used on the other ports
;	except that the SM83 is extra nasty as it lacks both xchg
;	and n,(ix) addressing approaches to get more effective registers
;	We end up using the carry flag at the end of each cycle to pass
;	the bit into the result.
;
;	Thankfully we have rl and the like on any register unlike 8080
;	
	ld	bc,0	; work register
	ld	a,16	; bits to do
	or	a	; carry clear
loop:
	push	af	; save count
	rl	l	; rotate the quotient through work clearing the low	
	rl	h
	rl	c
	rl	b	; drops bit into carry
	push	bc
	;
	;	Check if working exceeds divisor (DE)
	;
	ld	a,c
	sbc	e
	ld	c,a
	ld	a,b
	sbc	d
	ld	b,a	; BC is now the result if we want it
	;	Did it fit ?
	jr	nc, dosub
	pop	bc	; get the old value back
	pop	af	; counter
	dec	a	; C is not changed
	or	a	; clear carry
	jr	nz, loop
	jr	out
dosub:
	pop	af	; faster than 2 x inc sp on the SM83
	pop	af	; count back
	dec	a
	scf		; so we rotate in a 1 for this loop
	jr	nz, loop
out:
	; shift the last bit in
	rl	l
	rl	h
	ld	e,c	; We need to restore BC so return in DE
	ld	c,b
	pop	bc
	ret

;	(DE) / HL
__div2op:
	push	de	; no XCHG on SM83
	push	hl
	pop	de
	pop	hl
	; (HL) / DE
	ldi	a,(hl)
	ld	h,(hl)
	ld	l,a
__div2opcon:
	push	bc
	ld	c,0
	call	dodiv2opcon
	bit	0,c
	pop	bc
	ret	z
	jp	__negate
	
;	(DE) / HL
__rem2op:
	push	de	; no XCHG on SM83
	push	hl
	pop	de
	pop	hl
	; (HL) / DE
	ldi	a,(hl)
	ld	h,(hl)
	ld	l,a
__rem2opcon:
	push	bc
	ld	c,128
	call	dodiv2opcon
	ld	l,e
	ld	h,d
	bit	0,c
	pop	bc
	ret	z
	jp	__negate

;	(DE) / HL
__div2opu:
	push	de	; no XCHG on SM83
	push	hl
	pop	de
	pop	hl
	; (HL) / DE
	ldi	a,(hl)
	ld	h,(hl)
	ld	l,a
__div2opconu:
	; HL / DE
	call	__divhlde
	ret

;	(DE) % HL
__rem2opu:
	push	de	; no XCHG on SM83
	push	hl
	pop	de
	pop	hl
	; (HL) % DE
	ldi	a,(hl)
	ld	h,(hl)
	ld	l,a
__rem2opconu:
	; HL % DE
	call __divhlde
	ld l,e
	ld h,d
	ret
