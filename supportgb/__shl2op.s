;
;	DE << (HL)
;
	.export	__shl2op

__shl2op:
	ld	a,(hl)
	and	15
	ret	z
loop:
	sla	e
	rl	d
	dec	a
	jr	nz, loop
	ret

