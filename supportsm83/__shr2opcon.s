;
;	DE >> L signed
;
	.export __shr2opcon


__shr2opcon:
	ld	a,l
	and	15
	ret	z
loop:
	sra	d
	rr	e
	dec	a
	jr	nz, loop
	ret

	