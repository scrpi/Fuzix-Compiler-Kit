	.setcpu 4
	.export __ccgtl
	.export __ccgtul

	.code

;	TOS  < hireg:B
__ccgtl:
	; Long math we want to do hireg first
	stx (-s)
	lda (__hireg)
	ldx 4(s)		; high word
	sub a,x
	bz ccgt2
	ble true
false:	ldx (s+)
 	inr s
	inr s
	inr s
	inr s
	clr b
	rsr
true:
	ldx (s+)
 	inr s
	inr s
	inr s
	inr s
	ldb 1
	rsr

__ccgtul:
	stx (-s)
	lda (__hireg)
	ldx 4(s)
	sub a,x
	bz ccgt2
	bl false
	bnl true
ccgt2:
	lda 6(s)
	sub b,a
	bz false
	bl true
	bra false
