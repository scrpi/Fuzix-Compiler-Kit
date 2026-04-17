;
;	DE << (HL)
;
	.export	__shr2op

__shr2op:
	ld	a,(hl)
	ld	l,e
	ld	h,d
	and	15
	ret	z
loop:
	sra	h
	rr	l
	dec	a
	jr	nz, loop
	ret

