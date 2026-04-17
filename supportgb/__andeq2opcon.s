;
;	(DE) & HL
;
	.export __andeq2opcon

__andeq2opcon:
	ld 	a,(de)
	and	h
	ld	(de),a
	ld	h,a
	inc	de
	ld	a,(de)
	and	l
	ld	(de),a
	ld	l,a
	ret

