;
;	HL = DE
;
;	TODO: in the backend generate the DE load when possible as negative
;	and use ADD instead
;
	.export __cceq
	.export __cmpeq
	.export __cmpeqcon

__cceq:
	pop	bc
	pop	hl
	push	bc
	jr	__cmpeqcon
__cmpeq:
	ldi	a,(hl)
	ld	h,(hl)
	ld	l,a
__cmpeqcon:
	ld	a,h
	xor	d
	jr	nz,false
	ld	a,l
	xor	e
	jr	nz,false
	ld	de,0
	inc	e
	ret
false:	xor	a
	ld	e,a
	ret
