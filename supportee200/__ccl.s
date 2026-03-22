;
;	Long signed compares. We have to handle the flag xor ourselves
;	Compare hireg:B with TOS

	.setcpu	4
	.export __ccltl
	.export __ccltul
	.export __cclteql
	.export __ccltequl
	.export __ccgtl
	.export __ccgtul
	.export __ccgteql
	.export __ccgtequl

__ccgteql:
	stx	(-s)
	lda	(__hireg);	high
	ldx	4(s)	;	high other
	sub	x,a	;	check high
	bz	ccgteq2	;	check low bytes as if unsigned
	bm	invertedg
as_gteq:
	bnf	true
	bra	false

invertedg:	; sign is negative
	bnf	false
	bra	true

__ccgtequl:
	stx	(-s)
	lda	(__hireg)
	ldx	4(s)
	sub	x,a
	bz	ccgteq2
	bl	true
	bra	false
ccgteq2:
	lda	6(s)
	sab
	bz	true
	bl	true
	bra	false


__ccgtl:
	stx	(-s)
	lda	(__hireg)
	ldx	4(s)
	sub	x,a
	bz	ccgt2
	bm	invertedg
	bra	as_gteq

__ccgtul:
	stx	(-s)
	lda	(__hireg)
	ldx	4(s)
	sub	x,a
	bz	ccgt2
	bl	true
	bra	false
ccgt2:
	lda	6(s)
	sab
	bz	false
	bl	true
	bra	false


__ccltl:
	stx	(-s)
	lda	(__hireg);	high
	ldx	4(s)	;	high other
	sub	x,a	;	check high
	bz	cclt2	;	check low bytes as if unsigned
	bm	inverted
as_lt:
	bf	true
false:	ldx	(s+)
	inr	s
	inr	s
	inr	s
	inr	s
	clr	b
	rsr
true:	ldx	(s+)
	inr	s
	inr	s
	inr	s
	inr	s
	ldb	1
	rsr

inverted:	; sign is negative
	bf	false
	bra	true

__ccltul:
	stx	(-s)
	lda	(__hireg)
	ldx	4(s)
	sub	x,a
	bz	cclt2
	bnl	true
	bra	false
cclt2:
	lda	6(s)
	sab
	bz	false
	bnl	true
	bra	false


__cclteql:
	stx	(-s)
	lda	(__hireg)
	ldx	4(s)
	sub	x,a
	bz	cclteq2
	bm	inverted
	bra	as_lt

__ccltequl:
	stx	(-s)
	lda	(__hireg)
	ldx	4(s)
	sub	x,a
	bz	cclteq2
	bnl	true
	bra	false
cclteq2:
	lda	6(s)
	sab
	bz	true
	bnl	true
	bra	false

