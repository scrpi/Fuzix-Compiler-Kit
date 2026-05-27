;
;	HL != DE
;
;	TODO: in the backend generate the DE load when possible as negative
;	and use ADD instead
;
	.export __ccne
	.export	__cmpne
	.export __cmpnecon

__ccne:
	pop	bc
	pop	hl
	push	bc
	jr	__cmpnecon
__cmpne:
	ldi	a,(hl)
	ld	h,(hl)
	ld	l,a
__cmpnecon:
	ld	a,h
	xor	d
	jr	nz,true
	ld	a,l
	xor	e
	jr	nz,true
	ld	de,0
	; Z is already set
	ret
true:	ld	de,1	; already NZ
	ret
