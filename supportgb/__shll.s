;
;	(TOS) << E
;
;	TODO: optimize shifts by 8 / 16 / 24
;
	.export __shll
	.export __shleql

__shll:
	ld	a,e
	ld	hl,sp+5
	call	do_shll
	pop	hl
	add	sp,4
	jp	(hl)

do_shll:
	ld	b,(hl)
	dec	hl
	ld	c,(hl)
	dec	hl
	ld	d,(hl)
	dec	hl
	ld	l,(hl)
	ld	h,d
	; BCHL << A
	and	31
	ret	z
	cp	16
	jr	c,loop
	call	nz, do16
	ld	b,h
	ld	c,l
	ld	de,0
	ret
do16:
	and	15
loop16:	add	hl,hl
	dec	a
	jr	nz,loop16
	ld	d,h
	ld	e,l
	ret

loop:
	add	hl,hl
	rl	c
	rl	b
	dec	a
	jr	nz,loop
	ld	d,h
	ld	e,l
	ret

__shleql:
	call	__eqprep
	; now HL is pointer E is shift
	push	hl
	inc	hl
	inc	hl
	inc	hl
	ld	a,e
	call	do_shll
	jp	__eqpopoutdebc
