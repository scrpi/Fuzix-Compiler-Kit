	.export __lstxa0
	.export __lstxa1
	.export __lstxa2
	.export __lstxa3
	.export __lstxa4
	.export __lstxay
	.code

; Compiler knows this increments Y

__lstxa4:
	ldy	#4
	bne	__lstxay
__lstxa3:
	ldy	#3
	bne	__lstxay
__lstxa2:
	ldy	#2
	bne	__lstxay
__lstxa1:
	ldy	#1
	bne	__lstxay
__lstxa0:
	ldy	#0
__lstxay:
	pha
	sta (@sp),y
	txa
	iny
	sta (@sp),y
	pla
	rts
