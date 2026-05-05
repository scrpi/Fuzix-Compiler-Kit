		.export __lshift1
		.code

__lshift1:
	stx	@tmp
	asl	a
	rol	@tmp
	ldx	@tmp
	rts
