;
;	Signed 32bit division and remainder
;
	.export	__divl
	.export __reml
	.export __diveql
	.export __remeql

__divl:
	ld	h,b		; save sign before negation
	bit	7,b
	call	nz, __negatel
	ld	a,h		; recover sign we saved
	ld	hl,sp+5
	xor	(hl)
	push	af		; save sign difference
	bit	7,(hl)
	call	nz, neghl
	; Both sides are now positive
	call	__div32
	; Result is on stack frame
	ld	hl,sp+7
	pop	af
	bit	7,a
	call	nz, neghl
	; Now load it 
	ld	hl,sp+2
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	inc	hl
	ld	c,(hl)
	inc	hl
	ld	b,(hl)
	pop	hl
	add	sp,4
	jp	(hl)

__reml:
	bit	7,b
	call	nz, __negatel
	ld	hl,sp+5
	bit	7,(hl)
	push	af
	call	nz, neghl
	call	__div32
	; Result is in BCDE
	pop	af
	call	nz, __negatel
	pop	hl
	add	sp,4
	jp	(hl)

__diveql:
	call	__eqprep
	push	hl		; save pointer
	push	bc
	push	de		; save divisor
	ld	a,b		; save high
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	inc	hl
	ld	c,(hl)
	inc	hl
	ld	b,(hl)		; variable into BCDE
	xor	b		; compare signs
	bit	7,a
	push	af
	bit	7,b
	call	nz,__negatel
	pop	af
	push	bc
	push	de
	push	af
	; saved
	ld	hl,sp+6
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	inc	hl
	ld	c,(hl)
	inc	hl
	ld	b,(hl)
	bit	7,b
	call	nz,__negatel
	push	hl		; dummy
	call	__div32
	pop	hl
	pop	af
	pop	de
	pop	bc		; result
eqout:
	call	nz,__negatel
	pop	af		; discard save
	pop	af
	pop	hl		; pointer
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

__remeql:
	call	__eqprep
	push	hl		; save pointer
	push	bc
	push	de		; save divisor
	ld	a,b		; save high
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	inc	hl
	ld	c,(hl)
	inc	hl
	ld	b,(hl)		; variable into BCDE
	bit	7,b
	push	af		; save sign
	call	nz, __negatel
	pop	af
	push	bc
	push	de
	push	af
	; saved
	ld	hl,sp+4
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	inc	hl
	ld	c,(hl)
	inc	hl
	ld	b,(hl)
	bit	7,b
	call	nz,__negatel
	push	hl		; dummy
	call	__div32
	pop	hl
	pop	af
	inc	sp
	inc	sp
	inc	sp
	inc	sp
	jr	eqout

neghl:	; Negate the 32bit value at HL (pointer is top top byte)
	ld	a,(hl)
	cpl
	ldd	(hl),a
	ld	a,(hl)
	cpl	
	ldd	(hl),a
	ld	a,(hl)
	cpl
	ldd	(hl),a
	ld	a,(hl)
	cpl
	ld	(hl),a
	; HL points to low byte
	inc	(hl)
	ret	nz
	inc	hl
	inc	(hl)
	ret	nz
	inc	hl
	inc	(hl)
	ret	nz
	inc	hl
	inc	(hl)
	ret
