;
;	Shift right (TOS) by non constant B
;
	.setcpu	4
	.export __shreql

	.code

__shreql:
	stx	(-s)
	xfr	y,a
	sta	(-s)
	ldx	6(s)
	lda	31
	nab
	bz	nowork
	xfr	b,y
	lda	(x)
	ldb	2(x)
next:
	sra
	rrr	b
	dcr	y
	bnz	next
	sta	(x)
	stb	2(x)
out:
	sta	(__hireg)
	lda	(s+)
	xay
	ldx	(s+)
	inr	s
	inr	s
	rsr
nowork:
	lda	(x)
	ldb	2(x)
	bra	out
	