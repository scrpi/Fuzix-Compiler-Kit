;
;	HL << E
;
	.export __shl2opcon

__shl2opcon:
	ld	a,e
	and	15
	ret	z
loop:
	add	hl,hl
	dec	a
	jr	nz, loop
	ret

	