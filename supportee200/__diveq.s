	.setcpu 4
	.export __diveq
	.export __diveqc

	.code

__diveq:
	lda	2(s)
	lda	(a)
	stx	(-s)
	sta	(-s)
	jsr	__div
	; Removed the word we pushed. Result is in B
	ldx	(s+)
	lda	2(s)
	stb	(a)
	inr	s
	inr	s
	rsr

__diveqc:
	lda	2(s)
	ldab	(a)
	clrb	ah
	orib	al,al
	bp	ispve
	dcrb	ah
ispve:
	stx	(-s)
	sta	(-s)
	jsr	__div
	ldx	(s+)
	lda	2(s)
	stb	(a)
	inr	s
	inr	s
	rsr
