;
;	a >= @tmp signed
;
	.export	__gteqtmpc
	.export	__l_gteqtmpc
	.export __cclteqc

	.code

__cclteqc:
	jsr	__poptmp
	jmp	__gteqtmpc	
__l_gteqtmpc:
	jsr	__ytmpc
__gteqtmpc:
	ldx	#0
	sec
	sbc	@tmp
	bvc	l1
	eor	#$80
l1:
	bpl	true
	txa
	rts
true:
	lda	#1
	rts
