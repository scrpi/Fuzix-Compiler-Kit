;
;	We enter this with HL as the table and the value in A
;
	.export __switchc

__switchc:
	; We only allow a max of 256 switch entries for now
	ld	e,a
	ldi	a,(hl)
	or	a
	jr	z, match
	ld	d,a
	ld	a,e

next:
	inc	hl
	cp	(hl)		; match ?
	jr	z,match
	inc	hl
	inc	hl
	dec	d
	jr	nz, next
match:
	inc	hl
	; jump to the address in (hl)
	ldi	a,(hl)
	ld	h,(hl)
	ld	l,a
	jp	(hl)
