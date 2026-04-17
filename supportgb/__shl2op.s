;
;	DE << (HL)
;
	.export	__shl2op

__shl2op:
	ld	a,(hl)
	ld	l,e
	ld	h,d
	and	15
	ret	z
loop:
	add	hl,hl
	dec	a
	jr	nz, loop
	ret

