;
;	a >= @tmp unsigned
;
	.export	__gteqtmpuc
	.export	__l_gteqtmpuc
	.export  __ccltequc

	.code

__ccltequc:
	jsr	__poptmp
	jmp	__gteqtmpuc
__l_gteqtmpuc:
	jsr	__ytmpc
__gteqtmpuc:
	ldx	#0
	cmp	@tmp
	bcs	true
	txa
	rts
true:
	lda	#1
	rts
