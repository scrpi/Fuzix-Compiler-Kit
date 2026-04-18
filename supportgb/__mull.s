;
;	32bit multiply is a bit of a pain as we have few registers
;	and no indexed or short form accessors
;	As with 6800 do this in stripes
;


;
;	Our workspace is set up as 5 bytes
;	a counter then the sum. This allows us to ripple down
;	the memory despite the limitations of the CPU and use
;	ldi. As we have the workspace on the stack we can
;	quickly access parts of it
;
;
;	Our stack frame after set up looks like this
;
;
;	10-7	stacked 32bit argument
;	6-5	return address
;	4-0	workspace (counter and result)
;
	.export __mull
	.export __muleql

__mull:
	add	sp,-5		; make workspace
	ld	hl,sp+1
	xor	a
	ldi	(hl),a		; clear workspace
	ldi	(hl),a
	ldi	(hl),a
	ld	(hl),a

	; Now work through the maths
	ld	hl,sp+7
	ldi	a,(hl)
	call	mulstripe
	ld	hl,sp+8
	ldi	a,(hl)
	call	mulstripe
	ld	hl,sp+9
	ldi	a,(hl)
	call	mulstripe
	ld	hl,sp+10
	ldi	a,(hl)
	call	mulstripe
	; Result is now in WORK
	ld	hl,sp+1
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	inc	hl
	ld	c,(hl)
	inc	hl
	ld	b,(hl)
	ld	l,e
	ld	h,d
	; Now clean up the stack
	add	sp,5
	pop	de
	add	sp,4
	push	de
	; and done
	ret

mulstripe:	; BCDE * A
	or	a
	jr	z,shiftonly	; no additions this byte worth
	ld	hl,sp+0
	ld	(hl),8
stripeloop:
	ld	hl,sp+1
	rra
	jr	nc,noadd
	inc	hl
	ld	a,(hl)
	add	e
	ldi	(hl),a
	ld	a,(hl)
	adc	d
	ldi	(hl),a
	ld	a,(hl)
	add	c
	ldi	(hl),a
	ld	a,(hl)
	add	b
	ld	(hl),a
noadd:
	ld	hl,sp+WORK+4
	sla	(hl)
	dec	hl
	sla	(hl)
	dec	hl
	sla	(hl)
	dec	hl
	sla	(hl)
	dec	hl	; now points at counter
	dec	(hl)
	jr	nz, mulstripe
	ret

shiftonly:
	push	de
	ld	hl,sp+1
	ld	a,(hl)
	ld	(hl),0
	ld	e,(hl)
	ldi	(hl),a
	ld	a,(hl)
	ld	(hl),e
	inc	hl
	ld	e,(hl)
	ldi	(hl),a
	ld	(hl),e
	pop	de
	ret

__muleql:
	call	__eqprep
	; HL is now pointer
	push	hl
	; As multiply is transistive push existing argument
	push	bc
	push	de
	; Now fetch the other one
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	inc	hl
	ld	c,(hl)
	inc	hl
	ld	b,(hl)
	call	__mull
	; mull removed the arg we pushed
	; BCDE is now the result
	pop	hl
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

