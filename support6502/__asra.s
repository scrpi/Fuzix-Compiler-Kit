;
;	byte arithmetic rotates
;
	.export __asra4
	.export __asra5
	.export __asra6
	.export __asra7

	.code

__asra7:
	cmp	#0x80
	ror	a
__asra6:
	cmp	#0x80
	ror	a
__asra5:
	cmp	#0x80
	ror	a
__asra4:
	cmp	#0x80
	ror	a
;__asra3:
	cmp	#0x80
	ror	a
;__asra2:
	cmp	#0x80
	ror	a
;__asra1:
	cmp	#0x80
	ror	a
	rts