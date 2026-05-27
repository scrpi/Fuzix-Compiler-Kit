;
;	(TOS) >> E
;
	.export __shrl
	.export __shrul
	.export __shreql
	.export __shrequl

__shrul:
	ld	a,e
	ld	hl,sp+5
	call	do_shrul
	pop	hl
	add	sp,4
	jp	(hl)

do_shrul:
	ld	b,(hl)
pve:
	dec	hl
	ld	c,(hl)
	dec	hl
	ld	d,(hl)
	dec	hl
	ld	e,(hl)
	; BCDE >> A
	and	31
	ret	z
	cp	24
	jr	c, try16
	ld	e,b
	ld	bc,0
	ld	d,b
	and	7
	ret	z
loop8:
	srl	e
	dec	a
	jr	nz,loop8
	ret
try16:
	cp	16
	jr	c, loop32
	ld	d,b
	ld	e,c
	ld	bc,0
	and	15
	ret	z
loop16:
	srl	d
	rr	e
	dec	a
	jr	nz,loop16
	ret
loop32:
	srl	b
	rr	c
	rr	d
	rr	e
	dec	a
	jr	nz,loop32
	ret
__shrl:
	ld	a,e
	ld	hl,sp+5
	call	do_shrl
	pop	hl
	add	sp,4
	jp	(hl)

do_shrl:
	ld	b,(hl)
	bit	7,b
	; If top bit clear use the unsigned path for optimizations
	; TODO negative side optimizations
	jr	z, pve

	dec	hl
	ld	c,(hl)
	dec	hl
	ld	d,(hl)
	dec	hl
	ld	e,(hl)
	; BCDE >> A
	and	31
	ret	z
loop:
	sra	b
	rr	c
	rr	d
	rr	e
	dec	a
	jr	nz,loop
	ret

__shrequl:
	call	__eqprep
	; now HL is pointer E is shift
	push	hl
	inc	hl
	inc	hl
	inc	hl
	ld	a,e
	call	do_shrul
	jp	__eqpopoutdebc

__shreql:
	call	__eqprep
	; now HL is pointer E is shift
	push	hl
	inc	hl
	inc	hl
	inc	hl
	ld	a,e
	call	do_shrl
	jp	__eqpopoutdebc
