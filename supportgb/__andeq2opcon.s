;
;	(HL) & DE
;
	.export __andeq2opcon

__andeq2opcon:
	ld 	a,(hl)
	and	e
	ldi	(hl),a
	ld	e,a
	ld	a,(hl)
	and	d
	ld	(hl),a
	ld	h,a
	ld	l,e
	ret

