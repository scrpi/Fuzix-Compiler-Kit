;
;	Clean up helper stack frames
;	Think about using DE for returns ?
;
	.export __popint
	.export __poplong

__popint:
	pop	de	; return
	inc	sp
	inc	sp
	push	de
	ret

__poplong:
	pop	de
	add	sp,4
	push	de
	ret
