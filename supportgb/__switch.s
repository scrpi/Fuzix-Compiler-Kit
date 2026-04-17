;
;	We enter this with HL as the table and the value in DE
;
	.export __switch

__switch:
	push	bc
	; We only allow a max of 256 switch entries for now
	ldi	a,(hl)
	or	a
	jr	z, default
	ld	c,a
next:
	inc	hl
	ldi	a,(hl)
	cp	e
	jr	nz, miss
	ld	a,(hl)
	cp	d
	jr	z, match
miss:	inc	hl
	inc	hl
	dec	c
	jr	nz, next
default:
match:
	; Matched
	inc	hl
	ldi	a,(hl)
	ld	h,(hl)
	ld	l,a
	pop	bc
	jp	(hl)
