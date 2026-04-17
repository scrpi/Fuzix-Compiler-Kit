;
;	Table in HL	match in BCDE
;
	.export __switchl

__switchl:
	ldi	a,(hl)
	inc	hl
	or	a
	jr	z,match
loop:
	push	af
	ldi	a,(hl)
	cp	e
	jr	nz,miss1
	ldi	a,(hl)
	cp	d
	jr	nz,miss2
	ldi	a,(hl)
	cp	c
	jr	nz,miss3
	ldi	a,(hl)
	cp	b
	jr	z,match
next:
	inc	hl
	inc	hl
	pop	af
	dec	a
	jr	nz, loop
match:
	ldi	a,(hl)
	ldi	h,(hl)
	ld	l,a
	pop	af
	jp	(hl)

miss1:	inc	hl
miss2:	inc	hl
miss3:	inc	hl
	jr	next
