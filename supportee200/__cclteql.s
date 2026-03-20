	.setcpu 4
	.export __cclteql
	.export __ccltequl

	.code

;	TOS  < hireg:B
__cclteql:
	; Long math we want to do hireg first
	stx (-s)
	lda (__hireg)
	ldx 4(s)		; high word
	sub a,x
	bz cclteq2
	ble false
true:	ldx (s+)
 	inr s
	inr s
	inr s
	inr s
	ldb 1
	rsr
false:
	ldx (s+)
 	inr s
	inr s
	inr s
	inr s
	clr b
	rsr

__ccltequl:
	stx (-s)
	lda (__hireg)
	ldx 4(s)
	sub a,x
	bz cclteq2
	bnl false
	bra true
cclteq2:
	lda 6(s)
	sub b,a
	bz true
	bnl false
	bra true
