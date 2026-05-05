		.export __lshift4
		.code

__lshift4:
	stx	@tmp
	asl	a
	rol	@tmp
	asl	a
	rol	@tmp
	asl	a
	rol	@tmp
	asl	a
	rol	@tmp
	ldx	@tmp
	rts
