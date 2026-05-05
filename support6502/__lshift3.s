		.export __lshift2
		.code

__lshift2:
	stx	@tmp1
	asl	a
	rol	@tmp1
	asl	a
	rol	@tmp1
	ldx	@tmp1
	rts
