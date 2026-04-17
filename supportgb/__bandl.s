;
;	BCHL & TOS
;
	.export __bandl

__bandl:
	ld	e,l
	ld	d,h
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
	ldi	a,(hl)
	and	b
	ld	b,a
	ld	h,d
	ld	l,e
	pop	de
	add	sp,4
	push	de
	ret
