	.setcpu 4
	.export __remequ
	.export __remequc

	.code

__remequ:
	lda	2(s)
	lda	(a)
	stx	(-s)
	sta	(-s)
	jsr	__remu
	; Removed the word we pushed. Result is in B
	ldx	(s+)
	lda	2(s)
	stb	(a)
	inr	s
	inr	s
	rsr

__remequc:
	lda	2(s)
	ldab	(a)
	clr	ah
	stx	(-s)
	sta	(-s)
	clr	bh
	jsr	__remu
	ldx	(s+)
	lda	2(s)
	stbb	(a)
	inr	s
	inr	s
	rsr
