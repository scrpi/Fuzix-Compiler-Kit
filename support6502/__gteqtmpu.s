;
;	xa >= @tmp unsigned
;
	.export __ccltequ
	.export	__gteqtmpu
	.export	__l_gteqtmpu

	.code

__l_gteqtmpu:
	jsr	__ytmp
	jmp	__gteqtmpu
__ccltequ:
	jsr	__poptmp
__gteqtmpu:
	cmp	@tmp
	txa
	ldx	#0
	sbc	@tmp+1
	bcs	true
	txa
	rts
true:
	lda	#1
	rts
