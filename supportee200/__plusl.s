	.setcpu 4
	.export __plusl

	.code

__plusl:
	; top of stack plus hireg:b
	lda	4(s)	; 2 is high 4 is low
	aab
	stb	4(s)	; use as a save for the low word
	lda	2(s)	; high half
	bnl	nocarry
	ina
nocarry:
	ldb	(__hireg)
	aab
	stb	(__hireg)
	ldb	4(s)	; get the low half back
	; now throw 4 bytes
	lda	4
	add	a,s
	rsr
