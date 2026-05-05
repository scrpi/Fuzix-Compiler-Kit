		.export __lshift3
		.code

__lshift3:
	stx	@tmp1
	asl	a
	rol	@tmp1
	asl	a
	rol	@tmp1
	asl	a
	rol	@tmp1
	ldx	@tmp1
	rts
