;
;	boolify DE
;
	.export __bool
	.export __not
	.export __cmpeq0
	.export __cmpne0

__bool:
__cmpne0:
	ld	a,d
	or	e
	ret	z
	ld	de,0
true:
	inc	e		; set flags
	ret

__not:
__cmpeq0:			; compare to 0 is not
	ld	a,d
	or	e
	jr	z, true
	xor	a
	ld	d,a
	ld	e,a
	ret
