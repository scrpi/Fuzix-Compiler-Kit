;
;	DE << L
;
	.export __shl2opcon

__shl2opcon:
	ld	a,l
	and	15
	ret	z
loop:
	sla	e
	rl	d
	dec	a
	jr	nz, loop
	ret

	