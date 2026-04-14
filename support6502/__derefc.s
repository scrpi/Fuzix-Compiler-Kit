	.export __derefc

	.code

__derefc:
	sta @tmp
	stx @tmp+1
	ldy #0
	lda (@tmp),y
	rts
