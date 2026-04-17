;
;	DE << (HL)
;
	.export	__shr2opu

__shr2opu:
	ld	a,(hl)
	ld	l,e
	ld	h,d
	and	15
	ret	z
loop:
	srl	h
	rr	l
	dec	a
	jr	nz, loop
	ret

