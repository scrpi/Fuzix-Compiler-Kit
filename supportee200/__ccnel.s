	.setcpu 4
	.export __ccnel

	.code
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
	; already 0 and Z
 	inr s
	inr s
	inr s
	inr s
	clr b		; force Z
	rsr
true:
 	inr s
	inr s
	inr s
	inr s
	ldb 1
	rsr
