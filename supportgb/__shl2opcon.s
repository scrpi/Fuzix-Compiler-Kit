;
;	HL >> E signed
;
__shr2opcon:
	ld	a,e
	and	15
	ret	z
loop:
	sra	h
	rr	l
	dec	a
	jr	nz, loop
	ret

	