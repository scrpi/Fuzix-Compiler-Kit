;
;	DE >> (HL)
;
	.export	__shr2op

__shr2op:
	ld	a,(hl)
	and	15
	ret	z
loop:
	sra	d
	rr	e
	dec	a
	jr	nz, loop
	ret

