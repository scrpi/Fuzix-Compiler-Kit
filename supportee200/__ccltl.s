	.setcpu 4
	.export __ccltl
	.export __ccltul

	.code

;	TOS  < hireg:B
__ccltl:
	; Long math we want to do hireg first
	stx (-s)
	lda (__hireg)
	ldx 4(s)		; high word
	sub x,a
	bz cclt2
	ble true
false:	ldx (s+)
 	inr s
	inr s
	inr s
	inr s
	clr b
	rsr
true:	ldx (s+)
 	inr s
	inr s
	inr s
	inr s
	ldb 1
	rsr

__ccltul:
	stx (-s)
	lda (__hireg)
	ldx 4(s)
	sub x,a
	bz cclt2
	bnl true
	bra false
cclt2:
	lda 6(s)
	; B = A - B
	sab
	bz false
	bnl true
	bra false
