	.setcpu 4
	.export __cceql
	.export __ccnel

	.code
__cceql:
	; 2,s is the high 4,s the low to comare with hireg:b
	; A is free
	lda 4(s)
	sab
	bnz false
	lda 2(s)
	ldb (__hireg)
	sab
	bnz false
true:
 	inr s
	inr s
	inr s
	inr s
	ldb 1
	rsr
false:
 	inr s
	inr s
	inr s
	inr s
	clr b
	rsr

__ccnel:
	; 2,s is the high 4,s the low to comare with hireg:b
	; A is free
	lda 4(s)
	sab
	bnz true
	lda 2(s)
	ldb (__hireg)
	sab
	bnz true
	bra false
