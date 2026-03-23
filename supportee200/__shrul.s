;
;	Shift right TOS by non constant B unsigned
;
	.setcpu	4
	.export __shrul

	.code

__shrul:
	stx	(-s)
	lda	31
	nab
	bz	nowork
	xfr	b,x
	lda	4(s)
	ldb	6(s)
	; First shift by hand
	rl
	rrr	a
	bra	go
next:
	sra
go:
	rrr	b
	dcx
	bnz	next
out:
	sta	(__hireg)
	ldx	(s+)
	lda	4
	add	a,s	; pull TOS out of the way
	rsr
nowork:
	lda	4(s)
	ldb	6(s)
	bra	out
	