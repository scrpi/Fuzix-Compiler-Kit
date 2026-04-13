	.export __deref

	.code

__deref:
	sta @tmp
	stx @tmp+1
	ldy #1
	lda (@tmp),y
	tax
	dey
	lda (@tmp),y
	rts
