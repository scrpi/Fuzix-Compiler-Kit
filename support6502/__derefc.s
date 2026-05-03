	.export __derefc
	.export __derefcy

	.code

__derefc:
	ldy #0
__derefcy:
	sta @tmp
	stx @tmp+1
	lda (@tmp),y
	ldx #0
	rts
