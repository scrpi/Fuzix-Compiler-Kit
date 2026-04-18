;
;	32bit divide
;
	.export __divul
	.export __remul
	.export __divequl
	.export __remequl
	.export __div32
;
;	The SM83 lacks xchg and also the ability to load
;	words into HL so a register based approach would be painful
;
;	Really though division consists of
;	- a 64bit rotate
;	- setting the low bit of the 64bit value
;	- a 32bit compare
;	- a 32bit subtract
;
;	All of those we can using (HL) and we can the ld hl,sp+n
;	instruction to set pointers into our workspace rapidly
;


;
;	After our set up the stack is
;
;
;	BCDE	divisor
;	9-12	input value
;	7-8	return address
;	5-6	return address
;	1-4	working
;	0	counter


__div32:
	add	sp,-5		; working value half and counter
	ld	hl,sp+0
	ld	(hl),32		; set counter
	inc	hl
	xor	a
	ldi	(hl),a
	ldi	(hl),a
	ldi	(hl),a
	ld	(hl),a
loop:	; low byte of input
	ld	hl,sp+9
	sla	(hl)
	inc	hl
	rl	(hl)
	inc	hl
	rl	(hl)
	inc	hl
	rl	(hl)		; rotated X left
	; low byte of working
	ld	hl,sp+1
	rl	(hl)
	inc	hl
	rl	(hl)
	inc	hl
	rl	(hl)
	inc	hl
	rl	(hl)		; rotate done
	; Rotation complete
	; Now check if working >= BCDE
	; working high
	ld	hl,sp+4
	ldd	a,(hl)
	cp	b
	jr	c,nope
	jr	nz,dosub
	ldd	a,(hl)
	cp	c
	jr	c,nope
	jr	nz,dosub
	ldd	a,(hl)
	cp	d
	jr	c,nope
	jr	nz,dosub
	ld	a,(hl)
	cp	e
	jr	c,nope
	; working low
dosub:	ld	hl,sp+1
	ld	a,(hl)
	sub	e
	ldi	(hl),a
	ld	a,(hl)
	sbc	d
	ldi	(hl),a
	ld	a,(hl)
	sbc	c
	ldi	(hl),a
	ld	a,(hl)
	sbc	b
	ld	(hl),a
	; Back to low of X
	ld	hl,sp+9
	inc	(hl)		; will always be 0 in low bit at this point
nope:
	ld	hl,sp+0
	dec	(hl)
	jr	nz, loop
	; work now holds the remainder, the input on the stack has been
	; replaced with the result.
	inc	hl
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	inc	hl
	ld	c,(hl)
	inc	hl
	ld	b,(hl)
	ld	l,e
	ld	h,d
	add	sp,5
	; Remainder in BCDE
	ret	


__divul:
	ld	e,l
	ld	d,h
	call	__div32
	pop	de		; return address
	pop	bc		; upper half
	pop	hl		; lower half
	push	de		; put return back
	ret

__remul:
	ld	e,l
	ld	d,h
	call	__div32
	pop	de		; return address
	add	sp,4
	push	de
	ret

__divequl:
	call	__eqprep
	push	hl
	push	bc
	push	de		; save divisor		
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	inc	hl
	ld	c,(hl)
	inc	hl
	ld	b,(hl)
	push	bc
	push	de		; push the value from the variable
	; points to our save
	ld	hl,sp+4
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	inc	hl
	ld	d,(hl)
	inc	hl
	ld	b,(hl)		; working value now correct
	push	hl		; dummy
	call	__div32
	pop	hl		; dummy
	; result is in stack frame
	pop	de
	pop	bc		; recover value
	jr	eqout

__remequl:
	call	__eqprep
	push	hl
	push	bc
	push	de
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	inc	hl
	ld	c,(hl)
	inc	hl
	ld	b,(hl)
	push	hl		; dummy
	call	__div32
	add	sp,6		; drop stack workspace and dummy
	; Result is BCDE
eqout:
	pop	hl		; destination address
	ld	(hl),e
	inc	hl
	ld	(hl),d
	inc	hl
	ld	(hl),c
	inc	hl
	ld	(hl),b
	pop	de
	inc	sp
	inc	sp
	push	de
	ret
