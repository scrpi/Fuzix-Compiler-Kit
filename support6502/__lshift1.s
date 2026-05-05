		.export __lshift1
		.code

__lshift1:
	stx	@tmp1
	asl	a
	rol	@tmp1
	ldx	@tmp1
	rts
