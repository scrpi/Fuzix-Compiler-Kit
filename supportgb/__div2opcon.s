;
;	Core division operation	HL / DE unsigned
;	Produces both result and remainder
;
	.export __divhlde

	.export __div2opcon
	.export __rem2opcon
	.export __div2uopcon
	.export __rem2uopcon

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
	dec	a	; C will be clear in all cases we loop
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

__div2opcon:
__rem2opcon:
	; TODO

__div2uopcon:
	; HL / DE
	call	__divhlde
	ret

__rem2uopcon:
	call	__divhlde
	ld	l,e
	ld	h,d
	ret
