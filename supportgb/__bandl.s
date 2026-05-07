;
;	BCDE & TOS
;
	.export __bandl

__bandl:
	ld	hl,sp+2
	ldi	a,(hl)
	and	e
	ld	e,a
	ldi	a,(hl)
	and	d
	ld	d,a
	ldi	a,(hl)
	and	c
	ld	c,a
	ld	a,(hl)
	and	b
	ld	b,a
	pop	hl
	add	sp,4
	jp	(hl)
