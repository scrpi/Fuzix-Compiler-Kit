;
;	32bit multiply
;
;
;	TOS * hireg:B
;
	.setcpu	4
	.export __mull
	.export __mullu

	.code

__mull:
__mullu:
	stx	(-s)
	xfr	y,x
	stx	(-s)
	xfr	z,x
	stx	(-s)

	lda	(__hireg)

	; AB is one half

	; YZ is the working sum

	ldx	32	; counter
	clr	y
	clr	z	; total
nextbit:
	slr	z
	rlr	y
	slr	b
	rlr	a
	bnl	noadd
	; A:B += other arg
	sta	(-s)	; save value we are working with to make space
	lda	10(s)	; high
	add	a,y
	lda	12(s)	; low
	add	a,z
	; Deal with carry by hand
	bnl	nocarry
	inr	y
nocarry:
	lda	(s+)	; get working value back
noadd:
	dcx
	bnz	nextbit
	; Result is now in Y:Z
	xfr	y,a
	sta	(__hireg)
	xfr	z,b
	lda	(s+)
	xay
	lda	(s+)
	xaz
	ldx	(s+)
	lda	4
	add	a,s	; Clean up caller frame
	rsr

