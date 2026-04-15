;
;	boolify HL
;
	.export __bool
	.export __not
	.export __cmpeq0

__bool:
	ld	a,h
	or	l
	ret	z
	ld	hl,0
true:
	inc	l		; set flags
	ret

__not:
__cmpeq0:			; compare to 0 is not
	ld	a,h
	or	l
	jr	z, true
	xor	a
	ld	h,a
	ld	l,a
	ret
