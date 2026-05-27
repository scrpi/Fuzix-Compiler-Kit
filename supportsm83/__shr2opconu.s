;
;	DE >> L signed
;
	.export __shr2opconu

__shr2opconu:
	ld	a,l
	and	15
	ret	z
loop:
	srl	d
	rr	e
	dec	a
	jr	nz, loop
	ret
