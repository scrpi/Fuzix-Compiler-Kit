	.export __lstxay
	.code

; Compiler knows this increments Y

__lstxay:
	pha
	sta (@sp),y
	txa
	iny
	sta (@sp),y
	pla
	rts
