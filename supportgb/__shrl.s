;
;	(TOS) >> L
;
;	TODO: optimize shifts by 8 / 16 / 24
;
	.export __shrl
	.export __shrul
	.export __shreql
	.export __shrequl

__shrul:
	ld	a,l
	ld	hl,sp+5
	call	do_shrul
	pop	de
	add	sp,4
	push	de
	ret

do_shrul:
	ld	b,(hl)
pve:
	dec	hl
	ld	c,(hl)
	dec	hl
	ld	d,(hl)
	dec	hl
	ld	h,(hl)
	ld	l,d
	; BCHL >> A
	and	31
	ret	z
	cp	24
	jr	c, try16
	ld	l,b
	ld	bc,0
	ld	h,b
	and	7
	ret	z
loop8:
	srl	h
	dec	a
	jr	nz,loop8
	ret
try16:
	cp	16
	jr	c, loop32
	ld	h,b
	ld	l,c
	ld	bc,0
	and	15
	ret	z
loop16:
	srl	h
	rr	l
	dec	a
	jr	nz,loop16
	ret
loop32:
	srl	b
	rr	c
	rr	h
	rr	l
	dec	a
	jr	nz,loop32
	ret

__shrl:
	ld	a,l	
	ld	hl,sp+5
	call	do_shrl
	pop	de
	add	sp,4
	push	de
	ret

do_shrl:
	ld	b,(hl)
	bit	7,(hl)
	; If top bit clear use the unsigned path as it will one day get
	; some optimizations, and it's easier to optimize this for negative
	; cases only
	jr	z, pve

	dec	hl
	ld	c,(hl)
	dec	hl
	ld	d,(hl)
	dec	hl
	ld	h,(hl)
	ld	l,d
	; BCHL >> A

	and	31
	ret	z
loop:
	sra	b
	rr	c
	rr	h
	rr	l
	dec	a
	jr	nz,loop

	pop	de
	add	sp,4
	push	de
	ret

__shrequl:
	call	__eqprep
	; now HL is pointer E is shift
	push	hl
	ld	a,e
	call	do_shrul
	jp	__eqpopouthlbc

__shreql:
	call	__eqprep
	; now HL is pointer E is shift
	push	hl
	ld	a,e
	call	do_shrl
	jp	__eqpopouthlbc
