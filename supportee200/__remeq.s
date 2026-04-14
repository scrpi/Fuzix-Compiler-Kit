	.setcpu 4
	.export __remeq
	.export __remeqc

	.code

__remeq:
	lda	2(s)
	lda	(a)
	stx	(-s)
	sta	(-s)
	jsr	__rem
	; Removed the word we pushed. Result is in B
	ldx	(s+)
	lda	2(s)
	stb	(a)
	inr	s
	inr	s
	rsr

__remeqc:
	lda	2(s)
	ldab	(a)
	clrb	ah
	clrb	bh
	orib	al,al
	bp	ispve
	dcrb	ah
ispve:
	orib	bl,bl
	bp	ispve2
	dcrb	bh
ispve2:
	stx	(-s)
	sta	(-s)
	jsr	__rem
	ldx	(s+)
	lda	2(s)
	stbb	(a)
	inr	s
	inr	s
	rsr
