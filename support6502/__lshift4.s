		.export __lshift4
		.code

__lshift4:
	stx	@tmp1
	asl	a
	rol	@tmp1
	asl	a
	rol	@tmp1
	asl	a
	rol	@tmp1
	asl	a
	rol	@tmp1
	ldx	@tmp1
	rts
