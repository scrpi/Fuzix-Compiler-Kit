;
;	Do a 32bit divide unsigned
;
	.setcpu	4
	.export __divul
	.export __remul
	.code

__divul:
	stx	(-s)
	sta	(-s)	; dummy
	stb	(-s)
	ldb	(__hireg)
	stb	(-s)
	jsr	div32x32
	; Result is in the original stacked value
	lda	10(s)
	ldb	12(s)
doul:
	sta	(__hireg)
	lda	6
	add	a,s	; remove arguments and dummy
	ldx	(s+)	; recover X
	lda	4	; clean up caller argument
	add	a,s
	rsr

__remul:
	stx	(-s)
	sta	(-s)	; dummy
	stb	(-s)
	ldb	(__hireg)
	stb	(-s)
	jsr	div32x32
	bra	doul
