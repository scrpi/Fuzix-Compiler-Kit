;
;	HL >> E signed
;
	.export __shr2opconu

__shr2opconu:
	ld	a,e
	and	15
	ret	z
loop:
	srl	h
	rr	l
	dec	a
	jr	nz, loop
	ret
