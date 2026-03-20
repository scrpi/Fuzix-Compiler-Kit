	.setcpu 4
	.export __ccgteql
	.export __ccgtequl

	.code

;	TOS  < hireg:B
__ccgteql:
	; Long math we want to do hireg first
	stx (-s)
	lda (__hireg)
	ldx 4(s)		; high word
	; A = false - A
	sub x,a
	bz ccgteq2
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

__ccgtequl:
	stx (-s)
	lda (__hireg)
	ldx 4(s)
	sub x,a
	bz ccgteq2
	bl true
	bra false
ccgteq2:
	lda 6(s)
	; B = A - B
	sab
	bz true
	bl true
	bra false
