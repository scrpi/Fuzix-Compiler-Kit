		.export __lshift2
		.code

__lshift2:
	stx	@tmp
	asl	a
	rol	@tmp
	asl	a
	rol	@tmp
	ldx	@tmp
	rts
