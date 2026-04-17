;
;	We enter this with HL as the table and the value in E
;
	.export __switchc

__switchc:
	; We only allow a max of 256 switch entries for now
	ldi	a,(hl)
	or	a
	jr	z, default
	ld	d,a
	ld	a,e

next:
	inc	hl
	cp	(hl)		; match ?
	inc	hl
	jr	z,match
	inc	hl
	dec	d
	jr	nz, next
default:
	inc	hl
match:
	; jump to the address in (hl)
	ldi	a,(hl)
	ld	h,(hl)
	ld	l,a
	jp	(hl)
