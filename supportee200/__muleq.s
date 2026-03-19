	.setcpu 4
	.export __muleq
	.export __mulequ
	.export __muleqc
	.export __mulequc

	.code

__muleq:
__mulequ:
	lda	2(s)
	lda	(a)
	stx	(-s)
	sta	(-s)
	jsr	__mul
	; Removed the word we pushed. Result is in B
	ldx	(s+)
	lda	2(s)
	stb	(a)
	inr	s
	inr	s
	rsr

__muleqc:
__mulequc:
	lda	2(s)
	ldab	(a)
	stx	(-s)
	sta	(-s)
	jsr	__mul
	ldx	(s+)
	lda	2(s)
	stb	(a)
	inr	s
	inr	s
	rsr
