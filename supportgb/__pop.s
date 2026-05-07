;
;	Clean up helper stack frames
;
	.export __popint
	.export __poplong

__popint:
	pop	hl	; return
	inc	sp
	inc	sp
	jp	(hl)

__poplong:
	pop	hl
	add	sp,4
	jp	(hl)
