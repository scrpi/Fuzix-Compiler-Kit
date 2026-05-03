	.export __deref
	.export __derefy

	.code

__deref:
	ldy #1
__derefy:
	sta @tmp
	stx @tmp+1
	lda (@tmp),y
	tax
	dey
	lda (@tmp),y
	rts
