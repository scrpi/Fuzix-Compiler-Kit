	.setcpu 4
	.export __divequ
	.export __divequc

	.code

__divequ:
	lda	2(s)
	lda	(a)
	stx	(-s)
	sta	(-s)
	jsr	__divu
	; Removed the word we pushed. Result is in B
	ldx	(s+)
	lda	2(s)
	stb	(a)
	inr	s
	inr	s
	rsr

__divequc:
	lda	2(s)
	ldab	(a)
	clr	ah
	stx	(-s)
	sta	(-s)
	jsr	__divu
	ldx	(s+)
	lda	2(s)
	stbb	(a)
	inr	s
	inr	s
	rsr
