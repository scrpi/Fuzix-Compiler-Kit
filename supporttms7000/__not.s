	.export __notl
	.export __not
	.export __notc
	

__notl:
	or r2,r5
	or r3,r5
__not:
	or r4,r5
	jz true
	movd %0,r5
	rets
true:	; r4/r5 is currently 0
	inc r5	; sets flags right too
	rets
__notc:
	clr r4
	or r5,r5
	jz true
	clr r5
	rets
	