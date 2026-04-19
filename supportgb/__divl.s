;
;	Signed 32bit division and remainder
;
	.export	__divl
	.export __reml
	.export __diveql
	.export __remeql

__divl:
	ld	d,b		; save sign before negation
	bit	7,b
	call	nz, __negatel
	ld	a,d		; recover sign we saved
	ld	d,h
	ld	e,l		; shuffle into DE
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
	ld	l,e
	ld	h,d
	pop	de
	add	sp,4
	push	de
	ret

__reml:
	bit	7,b
	call	nz, __negatel
	ld	d,h
	ld	e,l
	ld	hl,sp+5
	bit	7,(hl)
	push	af
	call	nz, neghl
	call	__div32
	; Result is in BCDE
	ld	l,e
	ld	h,d
	pop	af
	call	nz, __negatel
	pop	de
	add	sp,4
	push	de
	ret

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
	call	negbcde
	push	bc
	push	de
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
	call	nz,negbcde
	push	hl		; dummy
	call	__div32
	pop	hl
	pop	de
	pop	bc		; result
eqout:
	pop	af
	call	nz,negbcde
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
	ld	l,e
	ld	h,d
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
	xor	b		; compare signs
	bit	7,b
	push	af		; save sign
	call	negbcde
	push	bc
	push	de
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
	call	nz,negbcde
	push	hl		; dummy
	call	__div32
	add	sp,6		; clean up stack
	jr	eqout

negbcde:
	; Temporary fudge. Once we switch to using DE as working reg and
	; BCDE this will go away
	push	hl
	ld	h,d
	ld	l,e
	call	__negatel
	ld	d,h
	ld	e,l
	pop	hl
	ret

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
