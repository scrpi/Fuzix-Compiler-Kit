;
;	DE << (HL)
;
	.export	__shr2opu

__shr2opu:
	ld	a,(hl)
	and	15
	ret	z
loop:
	srl	d
	rr	e
	dec	a
	jr	nz, loop
	ret

